import { Account, AccountInterface } from "starknet";
import { DojoProvider } from "@dojoengine/core";

const NAMESPACE = import.meta.env.VITE_NAMESPACE;

export interface IWorld {
  actions: {
    play_game: (props: { account: AccountInterface }) => Promise<any>;
    spawn_fren: (props: { account: AccountInterface }) => Promise<any>;
    secret: (props: { account: AccountInterface }) => Promise<any>;
  };
}

export interface MoveProps {
  account: Account | AccountInterface;
}

const handleError = (action: string, error: unknown) => {
  console.error(`Error executing ${action}:`, error);
  throw error;
};

export const setupWorld = async (provider: DojoProvider): Promise<IWorld> => {
  const actions = () => ({
    play_game: async ({ account }: { account: AccountInterface }) => {
      try {
        return await provider.execute(
          account,
          {
            contractName: "dojo_frens",
            entrypoint: "play_game",
            calldata: [],
          },
          NAMESPACE
        );
      } catch (error) {
        handleError("play_game", error);
      }
    },
    spawn_fren: async ({ account }: { account: AccountInterface }) => {
      try {
        return await provider.execute(
          account,
          {
            contractName: "dojo_frens",
            entrypoint: "spawn_fren",
            calldata: [],
          },
          NAMESPACE
        );
      } catch (error) {
        handleError("spawn_fren", error);
      }
    },
    secret: async ({ account }: { account: AccountInterface }) => {
      try {
        return await provider.execute(
          account,
          {
            contractName: "dojo_frens",
            entrypoint: "secret",
            calldata: [],
          },
          NAMESPACE
        );
      } catch (error) {
        handleError("secret", error);
      }
    },
  });

  return { actions: actions() };
};
