import { getEntityIdFromKeys } from "@dojoengine/utils";
import {
  useComponentValue,
  useEntityQuery,
  useQuerySync,
} from "@dojoengine/react";
import { Entity, Has, HasValue, QueryFragment } from "@dojoengine/recs";
import { useDojo } from "../../dojo/useDojo";
import { useAccount } from "@starknet-react/core";
import { getSyncEntities } from "@dojoengine/state";
import { shortString } from "starknet";

export default function Quests() {
  const { account } = useAccount();
  const {
    setup: {
      systemCalls: { play_game, spawn_fren, secret },
      clientComponents: {/* Quest,*/ QuestCounter, QuestClaimed },
      clientComponents,
      toriiClient,
      contractComponents,
    },
  } = useDojo();

  const ns = import.meta.env.VITE_NAMESPACE;

  // getSyncEntities(
  //   toriiClient,
  //   { QuestCounter: clientComponents.QuestCounter } as any,
  //   []
  // );

  // const quests = useEntityQuery([Has(Quest)], { updateOnValueChange: true });
  // const questsCounter = useEntityQuery([Has(QuestCounter)], {
  //   updateOnValueChange: true,
  // });
  // const questsClaimed = useEntityQuery([Has(QuestClaimed)], {
  //   updateOnValueChange: true,
  // });

  // useQuerySync(toriiClient, contractComponents as any, [
  //   {
  //     Keys: {
  //       keys: [],
  //       models: [`${ns}-Quest`],
  //       pattern_matching: "FixedLen",
  //     },
  //   },
  // ]);

 
  // // console.log(["0", BigInt(account?.address || 0).toString()])

  useQuerySync(toriiClient, contractComponents as any, [
    {
      Keys: {
        //  keys: ["0x0", BigInt(account?.address || 0).toString()],
        keys: [""],
        // keys: [],
        // models: [`${ns}-QuestCounter`, `${ns}-QuestClaimed`],
        // models: [`${ns}-QuestCounter`],
       // models: [`${ns}-QuestCounter`],
        models: [`dojo_world-QuestCounter`],
        // models: [],
        pattern_matching: "VariableLen",
      
      },
    
    },
  ]);

  // entity id we are syncing
  const entityId = getEntityIdFromKeys([
    BigInt(account?.address || 0),
  ]) as Entity;

  //   // get current component values
  //   const quests = useComponentValue(Quest, entityId);
  //   const questsCounters = useComponentValue(QuestCounter, entityId);
  //   const questsClaimed = useComponentValue(QuestClaimed, entityId);

  if (!account) return null;
  return (
    <div>
      <h2>Quests</h2>
      <div> entityId: {entityId}</div>
      {/* <div> quests: {JSON.stringify(quests)}</div>
      <div> questsCounter: {JSON.stringify(questsCounter)}</div>
      <div> questsClaimed: {JSON.stringify(questsClaimed)}</div> */}

      <div style={{ display: "flex", justifyContent: "center", gap: "10px" }}>
        <button onClick={() => play_game(account)}>play_game</button>
        <button onClick={() => spawn_fren(account)}>spawn_fren</button>
        <button onClick={() => secret(account)}>secret</button>
      </div>
    </div>
  );
}
