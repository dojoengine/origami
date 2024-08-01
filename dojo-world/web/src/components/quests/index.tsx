import { getEntityIdFromKeys } from "@dojoengine/utils";
import {
  useComponentValue,
  useEntityQuery,
  useQuerySync,
} from "@dojoengine/react";
import { Entity, Has, HasValue, QueryFragment } from "@dojoengine/recs";
import { useDojo } from "../../dojo/useDojo";
import { useAccount } from "@starknet-react/core";

export default function Quests() {
  const { account } = useAccount();
  const {
    setup: {
      systemCalls: { play_game, spawn_fren, secret },
    //   clientComponents: { Quest, QuestCounter, QuestClaimed },
    //   toriiClient,
    //   contractComponents,
    },
  } = useDojo();

  const ns = import.meta.env.VITE_NAMESPACE;

    // const quests = useEntityQuery([Has(Quest)], { updateOnValueChange: true });

  //   useQuerySync(toriiClient, contractComponents as any, [
  //     {
  //       Keys: {
  //         keys: [],
  //         models: [`${ns}-Quest`],
  //         pattern_matching: "FixedLen",
  //       },
  //     },
  //   ]);

  //   useQuerySync(toriiClient, contractComponents as any, [
  //     {
  //       Keys: {
  //         keys: [BigInt(account?.address || 0).toString()],
  //         models: [`${ns}-QuestCounter`, `${ns}-QuestClaimed`],
  //         pattern_matching: "FixedLen",
  //       },
  //     },
  //   ]);

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
      {/* <div> quests: {JSON.stringify(quests)}</div> */}

      <div style={{ display: "flex", justifyContent: "center", gap: "10px" }}>
        <button onClick={() => play_game(account)}>play_game</button>
        <button onClick={() => spawn_fren(account)}>spawn_fren</button>
        <button onClick={() => secret(account)}>secret</button>
      </div>
    </div>
  );
}
