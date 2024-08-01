import { getSyncEntities } from "@dojoengine/state";
import { DojoConfig, DojoProvider } from "@dojoengine/core";
import * as torii from "@dojoengine/torii-client";
import { createClientComponents } from "../createClientComponents";
import { createSystemCalls } from "../createSystemCalls";
import { defineContractComponents } from "./contractComponents";
import { world } from "./world";
import { setupWorld } from "./generated";
import { Account, WeierstrassSignatureType } from "starknet";

export type SetupResult = Awaited<ReturnType<typeof setup>>;

export async function setup({ ...config }: DojoConfig) {
  // torii client
  const toriiClient = await torii.createClient({
    rpcUrl: config.rpcUrl,
    toriiUrl: config.toriiUrl,
    relayUrl: "",
    worldAddress: config.manifest.world.address || "",
  });

  // create contract components
  const contractComponents = defineContractComponents(world);

  // create client components
  const clientComponents = createClientComponents({ contractComponents });

  // fetch all existing entities from torii

  // create dojo provider
  const dojoProvider = new DojoProvider(config.manifest, config.rpcUrl);

  // setup world
  const client = await setupWorld(dojoProvider);

  return {
    client,
    clientComponents,
    contractComponents,
    systemCalls: createSystemCalls({ client }, clientComponents, world),
    publish: (typedData: string, signature: WeierstrassSignatureType) => {
      toriiClient.publishMessage(typedData, {
        r: signature.r.toString(),
        s: signature.s.toString(),
      });
    },
    config,
    dojoProvider,
    toriiClient,
    // sync,
  };
}
