"""Build the offline quick library from the publishers' public Arabic APIs.

Imports classical Arabic texts, citations and source grades, not modern hadith
commentary/translations. Keeps the five verified Quran presets in the base asset.
Cached requests make interrupted imports resumable. No account data is involved.
"""

import concurrent.futures
import hashlib
import html
import json
import re
import threading
import time
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.dart_tool' / 'quick_library_sources'
OUT = ROOT / 'assets' / 'data' / 'quick_content_library'
HADITH = 'https://hadeethenc.com/api/v1/'
HISN = 'https://www.hisnmuslim.com/api/ar/'
gate = threading.Lock()
next_request = 0.0


def fetch(url):
    global next_request
    file = CACHE / (hashlib.sha256(url.encode()).hexdigest() + '.json')
    if file.exists():
        try:
            return json.loads(file.read_text(encoding='utf-8'))
        except ValueError:
            pass  # Recover a cache file interrupted before a previous import finished.
    for attempt in range(4):
        with gate:
            delay = max(0, next_request - time.monotonic())
            next_request = max(next_request, time.monotonic()) + .3
        if delay:
            time.sleep(delay)
        request = urllib.request.Request(url, headers={
            'User-Agent': 'AZKAR-content-library/1.0', 'Accept': 'application/json',
        })
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                value = json.loads(response.read().decode('utf-8-sig'))
            temporary = file.with_suffix('.tmp')
            temporary.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
            temporary.replace(file)
            return value
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or attempt == 3:
                raise
            time.sleep(min(60, int(error.headers.get('Retry-After', '5')) * (attempt + 1)))
        except (TimeoutError, urllib.error.URLError):
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
    raise RuntimeError('Could not fetch source')


def clean(value):
    value = re.sub(r'<br\s*/?>', '\n', value or '', flags=re.I)
    return html.unescape(re.sub(r'<[^>]*>', '', value)).strip()


def comparison(value):
    return re.sub(r'[^\w]', '', re.sub(r'[\u064b-\u065f\u0670\u06d6-\u06edـ]', '', value))


def import_hadith():
    categories = fetch(HADITH + 'categories/list/?language=ar')
    names = {str(c['id']): clean(c['title']) for c in categories}
    roots = [c for c in categories if c.get('parent_id') is None]
    ids = set()
    for category in roots:
        first = fetch(HADITH + f'hadeeths/list/?language=ar&category_id={category["id"]}&page=1&per_page=20')
        ids.update(str(x['id']) for x in first['data'])
        for page in range(2, int(first['meta']['last_page']) + 1):
            result = fetch(HADITH + f'hadeeths/list/?language=ar&category_id={category["id"]}&page={page}&per_page=20')
            ids.update(str(x['id']) for x in result['data'])
        print(f'Hadith index: category {category["id"]}, {len(ids)} unique texts', flush=True)
    items, skipped, unavailable = [], Counter(), []

    def one(id):
        try:
            data = fetch(HADITH + f'hadeeths/one/?language=ar&id={id}')
        except (urllib.error.URLError, TimeoutError):
            unavailable.append(id)
            return None, 'source-unavailable'
        grade = clean(data.get('grade'))
        authenticity = ('sahih' if grade.startswith('صحيح') else
                        'hasan' if grade.startswith('حسن') else None)
        if authenticity is None or re.search('ضعيف|موضوع|منكر|لا يصح|لا يثبت|موقوف|مقطوع', grade):
            return None, 'unverified-grade'
        text = clean(data.get('hadeeth'))
        narrator = clean(data.get('hadeeth_intro'))
        reference = clean(data.get('reference'))
        if not narrator:
            prefix = re.split(r'[:：«"]', text, maxsplit=1)[0].strip()
            if len(prefix) < 600 and comparison(prefix).startswith(('عن', 'وعن')):
                narrator = prefix
        if not text or not reference:
            return None, 'missing-citation'
        first_reference = reference.splitlines()[0]
        numbers = re.findall(r'\((\d+)\)', first_reference)
        category_names = [names[str(c)] for c in data.get('categories', []) if str(c) in names]
        return {
            'id': 'hadeethenc-' + id, 'type': 'hadith',
            'title': clean(data['title']), 'text': text,
            'source': clean(data.get('attribution')) + ' — ' + first_reference,
            'url': 'https://hadeethenc.com/ar/browse/hadith/' + id,
            'narrator': narrator or None,
            'number': numbers[-1] if numbers else 'معرّف الموسوعة: ' + id,
            'authenticity': authenticity, 'sourceGrade': grade,
            'reference': reference, 'categories': category_names,
        }, None

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for index, (item, reason) in enumerate(pool.map(one, sorted(ids, key=int)), 1):
            if item:
                items.append(item)
            else:
                skipped[reason] += 1
            if index % 50 == 0 or index == len(ids):
                print(f'Hadith details: {index}/{len(ids)}, accepted={len(items)}', flush=True)
    if len(unavailable) > max(5, len(ids) // 100):
        raise RuntimeError('Source outage: refusing to replace the library with an incomplete import.')
    return items, {'indexed': len(ids), 'skipped': dict(skipped), 'unavailableIds': unavailable}


def import_hisn():
    index = next(iter(fetch(HISN + 'husn_ar.json').values()))
    items, skipped = [], Counter()
    for number, chapter in enumerate(index, 1):
        id = int(chapter['ID'])
        title = clean(chapter['TITLE'])
        entries = next(iter(fetch(HISN + f'{id}.json').values()))
        kind = 'dua' if re.search('دعاء|الدعاء|الدعوات|دعوة', title) else 'azkar'
        for position, entry in enumerate(entries, 1):
            text = clean(entry.get('ARABIC_TEXT'))
            # Quran choices are generated only from the app's verified dataset.
            if not text or any(mark in text for mark in ('﴿', '﴾', '{', '}')):
                skipped['quran-or-empty'] += 1
                continue
            repeat = int(entry.get('REPEAT') or 1)
            snippet = re.sub(r'\s+', ' ', text)[:58]
            items.append({
                'id': f'hisn-{id}-{entry["ID"]}', 'type': kind,
                'title': title + (' — ' + snippet if len(entries) > 1 else ''),
                'text': text, 'source': 'حصن المسلم — ' + title,
                'url': HISN + f'{id}.json', 'categories': [title],
                'repeat': repeat,
                **({'description': f'التكرار الوارد في المصدر: {repeat} مرات.'} if repeat > 1 else {}),
            })
        if number % 20 == 0 or number == len(index):
            print(f'Hisn chapters: {number}/{len(index)}, texts={len(items)}', flush=True)
    return items, {'chapters': len(index), 'skipped': dict(skipped)}


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    hadith, hadith_info = import_hadith()
    hisn, hisn_info = import_hisn()
    base = json.loads((ROOT / 'assets/data/quick_content_presets.json').read_text(encoding='utf-8'))['items']
    seen = {(item['type'], comparison(item.get('text', ''))) for item in base if item.get('text')}
    groups = {kind: [] for kind in ('azkar', 'dua', 'hadith')}
    for item in hisn + hadith:
        key = (item['type'], comparison(item['text']))
        if key in seen:
            continue
        seen.add(key)
        groups[item['type']].append(item)
    files = {}
    for kind, items in groups.items():
        data = (json.dumps({'version': 1, 'items': items}, ensure_ascii=False, separators=(',', ':')) + '\n').encode()
        (OUT / (kind + '.json')).write_bytes(data)
        files[kind] = {'items': len(items), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    manifest = {
        'version': 1, 'retrievedAtUtc': datetime.now(timezone.utc).isoformat(),
        'sources': [
            {'name': 'HadeethEnc official Arabic API', 'url': HADITH, **hadith_info},
            {'name': 'Hisn Al-Muslim Arabic publisher API', 'url': HISN, **hisn_info},
        ],
        'policy': 'Classical Arabic texts and citations only. Hadith source grade must be sahih/hasan. No modern explanations. Quran presets remain in the verified base dataset.',
        'files': files,
        'totalWithBase': len(base) + sum(len(v) for v in groups.values()),
    }
    (OUT / 'sources.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'extra': files, 'total': manifest['totalWithBase']}), flush=True)


if __name__ == '__main__':
    main()
