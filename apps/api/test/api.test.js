const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const app = require("../server");

function request(path) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, () => {
      const port = server.address().port;
      http.get(`http://localhost:${port}${path}`, (res) => {
        let body = "";
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () => {
          server.close();
          resolve({ status: res.statusCode, headers: res.headers, body: JSON.parse(body) });
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
    assert.ok(res.body.timestamp);
    assert.equal(res.headers["cache-control"], "no-store");
  });

  it("GET /api/time returns UTC time", async () => {
    const res = await request("/api/time");
    assert.equal(res.status, 200);
    assert.ok(res.body.utc);
    assert.ok(res.body.epoch);
  });

  it("GET /api/headers returns headers object", async () => {
    const res = await request("/api/headers");
    assert.equal(res.status, 200);
    assert.ok(res.body.headers);
    assert.ok(res.body.region);
  });

  it("GET /api/cache-control returns configurable cache", async () => {
    const res = await request("/api/cache-control?maxage=120");
    assert.equal(res.status, 200);
    assert.equal(res.headers["cache-control"], "public, max-age=120");
  });

  it("GET /api/cache-control with no-store policy", async () => {
    const res = await request("/api/cache-control?policy=no-store");
    assert.equal(res.status, 200);
    assert.equal(res.headers["cache-control"], "no-store");
  });

  it("GET /api/large returns 1000 items", async () => {
    const res = await request("/api/large");
    assert.equal(res.status, 200);
    assert.equal(res.body.count, 1000);
    assert.equal(res.body.items.length, 1000);
  });
});
