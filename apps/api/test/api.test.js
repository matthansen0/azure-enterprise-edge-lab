const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");

process.env.ORIGIN_LABEL = "test-origin";
process.env.AZURE_REGION = "test-region";

const app = require("../server");

function request(path, headers = {}) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, () => {
      const port = server.address().port;
      http.get(`http://localhost:${port}${path}`, { headers }, (res) => {
        let body = "";
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () => {
          server.close();
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: res.headers["content-type"]?.includes("application/json") ? JSON.parse(body) : body,
          });
        });
      }).on("error", (err) => { server.close(); reject(err); });
    });
  });
}

describe("API Endpoints", () => {
  it("GET /api/health returns healthy", async () => {
    const res = await request("/api/health");
    assert.equal(res.status, 200);
    assert.equal(res.body.status, "healthy");
    assert.equal(res.body.origin, "test-origin");
    assert.equal(res.body.region, "test-region");
    assert.ok(res.body.timestamp);
    assert.equal(res.headers["cache-control"], "no-store");
  });

  it("GET /api/time returns UTC time", async () => {
    const res = await request("/api/time");
    assert.equal(res.status, 200);
    assert.ok(res.body.utc);
    assert.ok(res.body.epoch);
    assert.equal(res.body.origin, "test-origin");
  });

  it("GET /api/headers returns headers object", async () => {
    const res = await request("/api/headers");
    assert.equal(res.status, 200);
    assert.ok(res.body.headers);
    assert.equal(res.body.origin, "test-origin");
    assert.ok(res.body.region);
  });

  it("GET /api/headers redacts credentials but retains Front Door headers", async () => {
    const res = await request("/api/headers", {
      authorization: "Bearer demo-not-a-secret",
      cookie: "demo=not-a-secret",
      "x-azure-ref": "demo-reference",
    });
    assert.equal(res.body.headers.authorization, undefined);
    assert.equal(res.body.headers.cookie, undefined);
    assert.equal(res.body.headers["x-azure-ref"], "demo-reference");
    assert.equal(res.headers["cache-control"], "no-store");
  });

  it("GET /api/cache-control returns configurable cache", async () => {
    const res = await request("/api/cache-control?maxage=120");
    assert.equal(res.status, 200);
    assert.equal(res.headers["cache-control"], "public, max-age=120");
    assert.equal(res.body.origin, "test-origin");
  });

  it("GET /api/cache-control with no-store policy", async () => {
    const res = await request("/api/cache-control?policy=no-store");
    assert.equal(res.status, 200);
    assert.equal(res.headers["cache-control"], "no-store");
    assert.equal(res.body.origin, "test-origin");
  });

  it("GET /api/cache-control retains the default TTL and caps the maximum", async () => {
    const defaultResponse = await request("/api/cache-control");
    assert.equal(defaultResponse.headers["cache-control"], "public, max-age=60");
    const capped = await request("/api/cache-control?maxage=90000");
    assert.equal(capped.headers["cache-control"], "public, max-age=86400");
    assert.equal(capped.body.requestedMaxAge, 90000);
  });

  it("GET /api/large returns 1000 items", async () => {
    const res = await request("/api/large");
    assert.equal(res.status, 200);
    assert.equal(res.body.count, 1000);
    assert.equal(res.body.items.length, 1000);
    assert.equal(res.body.origin, "test-origin");
  });

  describe("Static site and routing", () => {
    it("GET / serves the visual demo with a five-minute TTL", async () => {
      const res = await request("/");
      assert.equal(res.status, 200);
      assert.match(res.body, /<title>Enterprise Edge Platform<\/title>/);
      assert.equal(res.headers["cache-control"], "public, max-age=300");
    });

    for (const asset of ["style.css", "logo.svg"]) {
      it(`GET /static/${asset} has a one-year immutable TTL`, async () => {
        const res = await request(`/static/${asset}`);
        assert.equal(res.status, 200);
        assert.ok(res.body.length > 0);
        assert.equal(res.headers["cache-control"], "public, max-age=31536000, immutable");
      });
    }

    it("GET /static/version.json retains the short purge-demo TTL", async () => {
      const res = await request("/static/version.json");
      assert.equal(res.status, 200);
      assert.equal(res.headers["cache-control"], "public, max-age=30");
      assert.equal(typeof res.body.version, "string");
      assert.equal(typeof res.body.buildId, "string");
    });

    it("unknown routes return 404 rather than the homepage", async () => {
      assert.equal((await request("/api/missing")).status, 404);
      assert.equal((await request("/static/missing.css")).status, 404);
    });
  });
});
