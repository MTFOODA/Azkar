/// One binary file of an Arabic font family.
class FontAssetRef {
  const FontAssetRef({required this.path, required this.weight});

  /// Path relative to the Flutter asset bundle.
  final String path;

  /// The weight this binary should be registered for (used for static fonts).
  final int weight;
}

/// Immutable description of one selectable Arabic font family.
///
/// Exactly ten families are supported. Each is verified to be redistributable:
/// every family below is licensed under the SIL Open Font License 1.1, which
/// permits bundling and redistribution inside an application. The full license
/// text for each family is stored in `licenses/fonts/` (downloaded by
/// `tools/fetch_fonts.ps1`).
class ArabicFontSpec {
  const ArabicFontSpec({
    required this.id,
    required this.family,
    required this.labelAr,
    required this.labelEn,
    required this.descriptionAr,
    required this.assets,
    required this.variable,
    required this.license,
    this.minWeight = 400,
    this.maxWeight = 700,
  });

  /// Stable identifier persisted in the database (`font_family` column).
  final String id;

  /// The `fontFamily` name used by Flutter.
  final String family;

  final String labelAr;
  final String labelEn;
  final String descriptionAr;

  /// Registered binary files.
  final List<FontAssetRef> assets;

  /// Variable fonts expose a `wght` axis and are styled with `fontVariations`.
  final bool variable;

  /// License identifier plus copyright line.
  final String license;

  final int minWeight;
  final int maxWeight;

  /// Clamps an arbitrary requested weight into the range the family supports.
  int clampWeight(int weight) {
    if (weight < minWeight) return minWeight;
    if (weight > maxWeight) return maxWeight;
    return weight;
  }

  /// All asset paths, used for diagnostics and tests.
  List<String> get assetPaths =>
      assets.map((asset) => asset.path).toList(growable: false);
}

/// The curated catalogue of the ten Arabic font families offered to
/// administrators.
class ArabicFonts {
  const ArabicFonts._();

  static const String amiri = 'amiri';
  static const String cairo = 'cairo';
  static const String tajawal = 'tajawal';
  static const String notoNaskh = 'noto_naskh_arabic';
  static const String notoKufi = 'noto_kufi_arabic';
  static const String scheherazade = 'scheherazade_new';
  static const String reemKufi = 'reem_kufi';
  static const String lateef = 'lateef';
  static const String arefRuqaa = 'aref_ruqaa';
  static const String ibmPlexSansArabic = 'ibm_plex_sans_arabic';

  /// The family used when no explicit selection exists.
  static const String defaultFontId = amiri;

  /// The family used for Quranic text when an administrator did not choose one.
  static const String quranDefaultFontId = amiri;

  static const String _ofl = 'SIL Open Font License 1.1';

  static const List<ArabicFontSpec> all = <ArabicFontSpec>[
    ArabicFontSpec(
      id: amiri,
      family: 'Amiri',
      labelAr: 'أميري',
      labelEn: 'Amiri',
      descriptionAr: 'خط نسخي كلاسيكي أنيق، مناسب للنصوص الطويلة والآيات.',
      assets: <FontAssetRef>[
        FontAssetRef(path: 'assets/fonts/amiri/Amiri-Regular.ttf', weight: 400),
        FontAssetRef(path: 'assets/fonts/amiri/Amiri-Bold.ttf', weight: 700),
      ],
      variable: false,
      license: '$_ofl — Amiri (Khaled Hosny)',
    ),
    ArabicFontSpec(
      id: cairo,
      family: 'Cairo',
      labelAr: 'القاهرة',
      labelEn: 'Cairo',
      descriptionAr: 'خط حديث واضح الشكل، مثالي للعناوين والواجهات العصرية.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path: 'assets/fonts/cairo/Cairo-VariableFont.ttf',
          weight: 400,
        ),
      ],
      variable: true,
      license: '$_ofl — Cairo (Mohamed Gaber)',
      minWeight: 300,
      maxWeight: 900,
    ),
    ArabicFontSpec(
      id: tajawal,
      family: 'Tajawal',
      labelAr: 'تجوال',
      labelEn: 'Tajawal',
      descriptionAr: 'خط هندسي معاصر، خفيف ومقروء على الشاشات الصغيرة.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path: 'assets/fonts/tajawal/Tajawal-Regular.ttf',
          weight: 400,
        ),
        FontAssetRef(
          path: 'assets/fonts/tajawal/Tajawal-Medium.ttf',
          weight: 500,
        ),
        FontAssetRef(
          path: 'assets/fonts/tajawal/Tajawal-Bold.ttf',
          weight: 700,
        ),
      ],
      variable: false,
      license: '$_ofl — Tajawal (SIL International)',
    ),
    ArabicFontSpec(
      id: notoNaskh,
      family: 'NotoNaskhArabic',
      labelAr: 'نوتو نسخ',
      labelEn: 'Noto Naskh Arabic',
      descriptionAr: 'نسخي متوازن الدقة، تغطية واسعة للرموز القرآنية.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path:
              'assets/fonts/noto_naskh_arabic/NotoNaskhArabic-VariableFont.ttf',
          weight: 400,
        ),
      ],
      variable: true,
      license: '$_ofl — Noto Naskh Arabic (Google)',
    ),
    ArabicFontSpec(
      id: notoKufi,
      family: 'NotoKufiArabic',
      labelAr: 'نوتو كوفي',
      labelEn: 'Noto Kufi Arabic',
      descriptionAr: 'كوفي معاصر بخطوط مستقيمة، مناسب للعناوين والبطاقات.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path: 'assets/fonts/noto_kufi_arabic/NotoKufiArabic-VariableFont.ttf',
          weight: 400,
        ),
      ],
      variable: true,
      license: '$_ofl — Noto Kufi Arabic (Google)',
    ),
    ArabicFontSpec(
      id: scheherazade,
      family: 'ScheherazadeNew',
      labelAr: 'شهرزاد',
      labelEn: 'Scheherazade New',
      descriptionAr: 'نسخي تقليدي واسع التشكيل، ممتاز للنصوص المشكولة.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path: 'assets/fonts/scheherazade_new/ScheherazadeNew-Regular.ttf',
          weight: 400,
        ),
        FontAssetRef(
          path: 'assets/fonts/scheherazade_new/ScheherazadeNew-Bold.ttf',
          weight: 700,
        ),
      ],
      variable: false,
      license: '$_ofl — Scheherazade New (SIL International)',
    ),
    ArabicFontSpec(
      id: reemKufi,
      family: 'ReemKufi',
      labelAr: 'ريم كوفي',
      labelEn: 'Reem Kufi',
      descriptionAr: 'كوفي أنيق للعناوين القصيرة والشعارات.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path: 'assets/fonts/reem_kufi/ReemKufi-VariableFont.ttf',
          weight: 400,
        ),
      ],
      variable: true,
      license: '$_ofl — Reem Kufi (Khaled Hosny)',
    ),
    ArabicFontSpec(
      id: lateef,
      family: 'Lateef',
      labelAr: 'لطيف',
      labelEn: 'Lateef',
      descriptionAr: 'خفيف وسريع التحميل، مناسب للنصوص الكثيفة.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path: 'assets/fonts/lateef/Lateef-Regular.ttf',
          weight: 400,
        ),
        FontAssetRef(path: 'assets/fonts/lateef/Lateef-Bold.ttf', weight: 700),
      ],
      variable: false,
      license: '$_ofl — Lateef (SIL International)',
    ),
    ArabicFontSpec(
      id: arefRuqaa,
      family: 'ArefRuqaa',
      labelAr: 'عارف رقعة',
      labelEn: 'Aref Ruqaa',
      descriptionAr: 'خط رقعة فخم، يصلح للإهداءات والعبارات القصيرة.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path: 'assets/fonts/aref_ruqaa/ArefRuqaa-Regular.ttf',
          weight: 400,
        ),
        FontAssetRef(
          path: 'assets/fonts/aref_ruqaa/ArefRuqaa-Bold.ttf',
          weight: 700,
        ),
      ],
      variable: false,
      license: '$_ofl — Aref Ruqaa (Khaled Hosny)',
    ),
    ArabicFontSpec(
      id: ibmPlexSansArabic,
      family: 'IBMPlexSansArabic',
      labelAr: 'IBM بلكس',
      labelEn: 'IBM Plex Sans Arabic',
      descriptionAr: 'خط واجهات حديث عالي الوضوح للأحجام الصغيرة.',
      assets: <FontAssetRef>[
        FontAssetRef(
          path:
              'assets/fonts/ibm_plex_sans_arabic/IBMPlexSansArabic-Regular.ttf',
          weight: 400,
        ),
        FontAssetRef(
          path:
              'assets/fonts/ibm_plex_sans_arabic/IBMPlexSansArabic-Medium.ttf',
          weight: 500,
        ),
        FontAssetRef(
          path: 'assets/fonts/ibm_plex_sans_arabic/IBMPlexSansArabic-Bold.ttf',
          weight: 700,
        ),
      ],
      variable: false,
      license: '$_ofl — IBM Plex Sans Arabic (IBM)',
    ),
  ];

  static final Map<String, ArabicFontSpec> _byId = <String, ArabicFontSpec>{
    for (final spec in all) spec.id: spec,
  };

  static final Map<String, ArabicFontSpec> _byFamily = <String, ArabicFontSpec>{
    for (final spec in all) spec.family: spec,
  };

  static List<String> get ids =>
      all.map((spec) => spec.id).toList(growable: false);

  /// Returns the spec for [id], falling back to Amiri when the stored value is
  /// unknown (for example after a downgrade or a hand-edited row).
  static ArabicFontSpec byId(String? id) {
    if (id == null) return _byId[defaultFontId]!;
    return _byId[id] ?? _byId[defaultFontId]!;
  }

  static ArabicFontSpec? byFamily(String? family) {
    if (family == null) return null;
    return _byFamily[family];
  }

  /// Whether [id] is one of the ten supported families (exactly ten).
  static bool isSupported(String id) => _byId.containsKey(id);
}
