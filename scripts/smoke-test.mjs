import { test } from "node:test";
import assert from "node:assert/strict";

function baseUrl(value, name) {
  assert.ok(value, `${name} is required`);
  const url = new URL(value);
  assert.ok(url.protocol === "https:" || (
    url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)
  ), `${name} must use HTTPS (HTTP is allowed only for localhost)`);
  assert.equal(url.pathname, "/", `${name} must not contain a path`);
  assert.ok(!url.search && !url.hash && !url.username && !url.password, `${name} must be a plain origin URL`);
  return url.origin;
}

const base = baseUrl(process.env.SMOKE_BASE_URL, "SMOKE_BASE_URL");
const frontDoor = process.env.SMOKE_FRONT_DOOR === "true";
assert.ok(process.env.SMOKE_FRONT_DOOR === undefined || ["true", "false"].includes(process.env.SMOKE_FRONT_DOOR),
  "SMOKE_FRONT_DOOR must be true or false");
const targets = [{ name: "endpoint", url: base, expectedOrigin: process.env.SMOKE_EXPECTED_ORIGIN }];
for (const label of ["a", "b"]) {
  const key = `SMOKE_ORIGIN_${label.toUpperCase()}_URL`;
  if (process.env[key]) {
    targets.push({ name: `origin-${label}`, url: baseUrl(process.env[key], key), expectedOrigin: label });
  }
}
console.log(`Smoke scope: ${frontDoor ? "Front Door (including WAF, redirect and cache HIT)" : "application only; no edge assertions"}`);

async function request(base, path, options = {}) {
  return fetch(`${base}${path}`, {
    redirect: "manual",
    signal: AbortSignal.timeout(15000),
    ...options,
  });
}

for (const target of targets) {
  await test(`${target.name}: application regression`, async (t) => {
    await t.test("homepage and static assets retain their cache contracts", async () => {
      for (const [path, ttl, pattern] of [
        ["/", 300, /Enterprise Edge Platform/],
        ["/static/style.css", 31536000, /body/],
        ["/static/logo.svg", 31536000, /<svg/],
        ["/static/version.json", 30, /"buildId"/],
      ]) {
        const response = await request(target.url, path);
        assert.equal(response.status, 200, path);
        assert.match(response.headers.get("cache-control"), new RegExp(`(?:^|, )max-age=${ttl}(?:,|$)`), path);
        if (ttl === 31536000) assert.match(response.headers.get("cache-control"), /immutable/);
        assert.match(await response.text(), pattern, path);
      }
    });

    await t.test("health is healthy, identifies the origin and is never cached", async () => {
      for (let i = 0; i < 2; i++) {
        const response = await request(target.url, "/api/health");
        assert.equal(response.status, 200);
        assert.equal(response.headers.get("cache-control"), "no-store");
        if (frontDoor && target.name === "endpoint") assert.ok(response.headers.get("x-azure-ref"));
        const health = await response.json();
        assert.equal(health.status, "healthy");
        assert.ok(health.region);
        assert.ok(Number.isFinite(Date.parse(health.timestamp)));
        assert.ok(health.uptime >= 0);
        if (target.expectedOrigin) assert.equal(health.origin, target.expectedOrigin);
      }
    });

    await t.test("time and header echo retain no-store and redact credentials", async () => {
      const time = await request(target.url, "/api/time");
      assert.equal(time.status, 200);
      assert.equal(time.headers.get("cache-control"), "no-store");
      const body = await time.json();
      assert.ok(Number.isFinite(Date.parse(body.utc)));
      assert.equal(typeof body.epoch, "number");
      const headers = await request(target.url, "/api/headers", {
        headers: { authorization: "Bearer demo-not-a-secret", cookie: "demo=not-a-secret" },
      });
      assert.equal(headers.status, 200);
      assert.equal(headers.headers.get("cache-control"), "no-store");
      const echo = await headers.json();
      assert.ok(echo.headers);
      assert.equal(echo.headers.authorization, undefined);
      assert.equal(echo.headers.cookie, undefined);
    });

    await t.test("API query strings select distinct TTLs and no-store is respected", async () => {
      for (const ttl of [120, 240]) {
        const response = await request(target.url, `/api/cache-control?maxage=${ttl}`);
        assert.equal(response.status, 200);
        assert.equal(response.headers.get("cache-control"), `public, max-age=${ttl}`);
        assert.equal((await response.json()).requestedMaxAge, ttl);
      }
      const response = await request(target.url, "/api/cache-control?policy=no-store");
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("cache-control"), "no-store");
      await response.text();
    });

    await t.test("large payload and unknown routes work", async () => {
      const large = await request(target.url, "/api/large");
      assert.equal(large.status, 200);
      const body = await large.json();
      assert.equal(body.count, 1000);
      assert.equal(body.items.length, 1000);
      const missing = await request(target.url, "/api/missing");
      assert.equal(missing.status, 404);
      await missing.text();
    });
  });
}

if (frontDoor) {
  assert.equal(new URL(base).protocol, "https:", "Front Door checks require HTTPS");
  await test("Front Door: HTTP redirects to the same HTTPS URL", async () => {
    const response = await request(base.replace("https:", "http:"), "/api/health");
    assert.ok([301, 302, 307, 308].includes(response.status), `HTTP ${response.status}`);
    assert.equal(response.headers.get("location"), `${base}/api/health`);
    await response.text();
  });

  await test("Front Door: benign WAF demos block mixed-case matches, not normal requests", async () => {
    for (const [path, headers] of [
      ["/api/health", { "X-Demo-Block": "TrUe" }],
      ["/?WaF-TeSt=BlOcK", {}],
      ["/api/health", { "User-Agent": "DemoMaliciousBot/1.0" }],
    ]) {
      const response = await request(base, path, { headers });
      assert.equal(response.status, 403, `${path} ${JSON.stringify(headers)}`);
      await response.text();
    }
    const response = await request(base, "/api/health", { headers: { "X-Demo-Block": "false" } });
    assert.equal(response.status, 200);
    await response.text();
  });

  await test("Front Door: repeated static requests produce a cache HIT", async () => {
    for (let attempt = 0; attempt < 6; attempt++) {
      const response = await request(base, "/static/style.css");
      assert.equal(response.status, 200);
      const cache = response.headers.get("x-cache") ?? "";
      await response.text();
      if (cache.includes("HIT")) return;
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    assert.fail("No x-cache HIT after six static requests");
  });
}
