const express = require("express");
const path = require("path");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 8080;
const REGION = process.env.WEBSITE_SITE_NAME || os.hostname();

// --------------- Static Site ---------------
// Serve static-site files from /static and root
// In dev: ../static-site, in deployed App Service: ./static-site (sibling in zip)
const fs = require("fs");
const devPath = path.join(__dirname, "..", "static-site");
const deployedPath = path.join(__dirname, "static-site");
const staticSitePath = fs.existsSync(deployedPath) ? deployedPath : devPath;

// Static assets with long cache
app.use(
  "/static",
  express.static(path.join(staticSitePath, "static"), {
    maxAge: "1y",
    immutable: true,
    setHeaders: (res, filePath) => {
      // version.json gets short cache for purge demo
      if (filePath.endsWith("version.json")) {
        res.setHeader("Cache-Control", "public, max-age=30");
      }
    },
  })
);

// Root HTML with moderate cache
app.get("/", (req, res) => {
  res.setHeader("Cache-Control", "public, max-age=300");
  res.sendFile(path.join(staticSitePath, "index.html"));
});

// --------------- API Endpoints ---------------

// Health check — no caching
app.get("/api/health", (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json({
    status: "healthy",
    region: REGION,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// Current time — no caching
app.get("/api/time", (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json({
    utc: new Date().toISOString(),
    epoch: Date.now(),
    region: REGION,
  });
});

// Echo request headers — useful to show Front Door injected headers
app.get("/api/headers", (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  // Filter out cookie/auth headers for safety
  const safeHeaders = { ...req.headers };
  delete safeHeaders.cookie;
  delete safeHeaders.authorization;
  res.json({
    headers: safeHeaders,
    clientIp: req.headers["x-forwarded-for"] || req.socket.remoteAddress,
    region: REGION,
  });
});

// Configurable cache control endpoint
app.get("/api/cache-control", (req, res) => {
  const maxAge = parseInt(req.query.maxage) || 60;
  const cacheHeader =
    req.query.policy === "no-store"
      ? "no-store"
      : `public, max-age=${Math.min(maxAge, 86400)}`;
  res.setHeader("Cache-Control", cacheHeader);
  res.json({
    cacheControl: cacheHeader,
    requestedMaxAge: maxAge,
    region: REGION,
    generatedAt: new Date().toISOString(),
  });
});

// Large payload — demonstrates compression and chunked transfer
app.get("/api/large", (req, res) => {
  res.setHeader("Cache-Control", "public, max-age=3600");
  const items = [];
  for (let i = 0; i < 1000; i++) {
    items.push({
      id: i,
      name: `Item ${i}`,
      description: `This is a sample item number ${i} used to demonstrate large payload delivery through the CDN edge with compression enabled.`,
      tags: ["demo", "large-payload", "cdn", `group-${i % 10}`],
    });
  }
  res.json({ count: items.length, region: REGION, items });
});

// --------------- Start ---------------
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`API server listening on port ${PORT} (region: ${REGION})`);
  });
}

module.exports = app;
