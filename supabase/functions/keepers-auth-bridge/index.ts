/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

import "./handler.js";

declare global {
  var keepersAuthBridge: {
    handleAuthBridgeRequest(request: Request): Response;
  };
}

Deno.serve((request) => globalThis.keepersAuthBridge.handleAuthBridgeRequest(request));
