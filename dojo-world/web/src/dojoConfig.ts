import manifest from "../../../dojo-world/manifests/dev/deployment/manifest.json";

import { createDojoConfig } from "@dojoengine/core";

export const dojoConfig = createDojoConfig({
  rpcUrl: import.meta.env.VITE_RPC_SEPOLIA,
  toriiUrl: import.meta.env.VITE_TORII_URL,

  manifest,
});
