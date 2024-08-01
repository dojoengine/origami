import { AccountInterface } from "starknet";
import {
  Entity,
  Has,
  HasValue,
  World,
  defineSystem,
  getComponentValue,
} from "@dojoengine/recs";
import { uuid } from "@latticexyz/utils";
import { ClientComponents } from "./createClientComponents";
// import { Direction, updatePositionWithDirection } from "../utils";
import { getEntityIdFromKeys } from "@dojoengine/utils";
import type { IWorld } from "./generated/generated";

export type SystemCalls = ReturnType<typeof createSystemCalls>;

export function createSystemCalls(
  { client }: { client: IWorld },
  { Quest, QuestCounter, QuestClaimed }: ClientComponents,
  world: World
) {
  const play_game = async (account: AccountInterface) => {
    try {
      await client.actions.play_game({
        account,
      });
    } catch (e) {
      console.log(e);
    }
  };

  const spawn_fren = async (account: AccountInterface) => {
    try {
      await client.actions.spawn_fren({
        account,
      });
    } catch (e) {
      console.log(e);
    }
  };

  const secret = async (account: AccountInterface) => {
    try {
      await client.actions.secret({
        account,
      });
    } catch (e) {
      console.log(e);
    }
  };

  return {
    play_game,
    spawn_fren,
    secret,
  };
}
