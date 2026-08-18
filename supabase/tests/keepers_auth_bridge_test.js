(async function runAuthBridgeTests() {
  "use strict";

  const tests = [];

  function test(name, body) {
    tests.push({ name, body });
  }

  function assert(condition, message) {
    if (!condition) {
      throw new Error(message);
    }
  }

  function assertEqual(actual, expected, label) {
    assert(
      actual === expected,
      `${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }

  function request(path, { method = "GET", userAgent = "Keepers test client" } = {}) {
    return {
      url: `https://example.supabase.co/functions/v1/keepers-auth-bridge${path}`,
      headers: new Headers({ "user-agent": userAgent }),
      method,
    };
  }

  async function readText(response) {
    const body = await response.text();
    assertEqual(
      response.headers.get("content-type"),
      "text/plain; charset=utf-8",
      "plain-text content type",
    );
    return body;
  }

  test("a valid code redirects iOS and general clients to the safely encoded Keepers callback", async function () {
    const userAgents = [
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
      "Keepers test client",
    ];

    for (const userAgent of userAgents) {
      const response = globalThis.keepersAuthBridge.handleAuthBridgeRequest(
        request("?code=alpha%2B%2F%26%22%3Ctag%3E", { userAgent }),
      );
      const body = await response.text();

      assertEqual(response.status, 303, `status for ${userAgent}`);
      assertEqual(
        response.headers.get("location"),
        "keepers://auth-callback?code=alpha%2B%2F%26%22%3Ctag%3E",
        `redirect for ${userAgent}`,
      );
      assertEqual(body, "", "redirect body");
      assertEqual(response.headers.get("content-type"), null, "redirect content type");
      assertEqual(response.headers.get("cache-control"), "no-store", "cache policy");
      assertEqual(response.headers.get("referrer-policy"), "no-referrer", "referrer policy");
      assertEqual(
        response.headers.get("x-content-type-options"),
        "nosniff",
        "content type protection",
      );
    }
  });

  test("a valid code redirects Android clients through the installed Keepers package", async function () {
    const response = globalThis.keepersAuthBridge.handleAuthBridgeRequest(
      request("?code=alpha%2B%2F%26%22%3Ctag%3E", {
        userAgent: "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36",
      }),
    );
    const body = await response.text();

    assertEqual(response.status, 303, "status");
    assertEqual(
      response.headers.get("location"),
      "intent://auth-callback?code=alpha%2B%2F%26%22%3Ctag%3E#Intent;scheme=keepers;package=app.keepers.keepers;end",
      "Android package redirect",
    );
    assertEqual(body, "", "redirect body");
    assertEqual(response.headers.get("content-type"), null, "redirect content type");
  });

  test("missing, empty, duplicate, and oversized codes are rejected without an app link", async function () {
    const invalidPaths = [
      "",
      "?code=",
      "?code=%20%20%20",
      "?code=first&code=second",
      "?code=valid&next=https%3A%2F%2Fexample.com",
      `?code=${"a".repeat(2049)}`,
    ];

    for (const path of invalidPaths) {
      const response = globalThis.keepersAuthBridge.handleAuthBridgeRequest(request(path));
      const body = await readText(response);

      assertEqual(response.status, 400, `status for ${path.slice(0, 40)}`);
      assert(
        !body.includes("keepers://") && !body.includes("intent://") && !body.includes("code="),
        "invalid response must not contain a callback or code",
      );
      assert(
        body.includes("Request a new sign-in link"),
        "invalid response must explain how to recover",
      );
    }
  });

  test("non-GET requests are rejected with an Allow header", async function () {
    const response = globalThis.keepersAuthBridge.handleAuthBridgeRequest(
      request("?code=valid", { method: "POST" }),
    );
    const body = await readText(response);

    assertEqual(response.status, 405, "status");
    assertEqual(response.headers.get("allow"), "GET", "allowed method");
    assert(
      !body.includes("keepers://") && !body.includes("intent://") && !body.includes("valid"),
      "method error must not expose an app link or authentication code",
    );
  });

  const failures = [];

  for (const current of tests) {
    try {
      await current.body();
    } catch (error) {
      failures.push(`${current.name}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  const output = document.getElementById("result");
  if (failures.length > 0) {
    document.title = "FAIL";
    output.textContent = `FAIL\n${failures.join("\n")}`;
    return;
  }

  document.title = "PASS";
  output.textContent = `PASS (${tests.length} tests)`;
})();
