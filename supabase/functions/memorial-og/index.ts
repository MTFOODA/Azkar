const htmlEscape = (value: string): string =>
  value.replace(/[&<>"']/g, (character) => {
    switch (character) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      default:
        return "&#39;";
    }
  });

Deno.serve(async (request) => {
  const projectUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const publicBaseUrl = Deno.env.get("PUBLIC_BASE_URL")?.replace(/\/+$/, "");
  const requestUrl = new URL(request.url);
  const slug = requestUrl.searchParams.get("slug") ?? "";

  if (!projectUrl || !anonKey || !publicBaseUrl) {
    return new Response("Preview metadata is not configured.", {
      status: 503,
    });
  }
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
    return new Response("Page not found.", { status: 404 });
  }

  const query = new URLSearchParams({
    select: "slug,title,description,deceased_name,dedication_message",
    slug: `eq.${slug}`,
    is_published: "eq.true",
    limit: "1",
  });
  const result = await fetch(
    `${projectUrl.replace(/\/+$/, "")}/rest/v1/memorial_pages?${query}`,
    {
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${anonKey}`,
        accept: "application/json",
      },
    },
  );
  if (!result.ok) {
    console.error("Public page metadata query failed", result.status);
    return new Response("Page preview is temporarily unavailable.", {
      status: 502,
    });
  }

  const pages = await result.json();
  const page = Array.isArray(pages) ? pages[0] : null;
  if (!page) return new Response("Page not found.", { status: 404 });

  const canonicalUrl = `${publicBaseUrl}/m/${encodeURIComponent(page.slug)}`;
  const title = htmlEscape(page.title || page.deceased_name || "AZKAR");
  const description = htmlEscape(
    page.description || page.dedication_message || page.title || "AZKAR",
  );
  const image = htmlEscape(`${publicBaseUrl}/icons/Icon-512.png`);
  const canonical = htmlEscape(canonicalUrl);
  const document = `<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title} | AZKAR</title>
  <meta name="description" content="${description}">
  <link rel="canonical" href="${canonical}">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${title} | AZKAR">
  <meta property="og:description" content="${description}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="${image}">
  <meta name="twitter:card" content="summary_large_image">
  <meta http-equiv="refresh" content="0;url=${canonical}">
</head>
<body><a href="${canonical}">${title}</a>
</body>
</html>`;

  return new Response(document, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=60, s-maxage=300",
      "x-content-type-options": "nosniff",
    },
  });
});
