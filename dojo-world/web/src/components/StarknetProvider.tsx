import { Chain, mainnet, sepolia } from "@starknet-react/chains";
import { Connector, StarknetConfig, starkscan } from "@starknet-react/core";
import { PropsWithChildren } from "react";
import CartridgeConnector from "@cartridge/connector";
import { RpcProvider, shortString } from "starknet";

export function StarknetProvider({ children }: PropsWithChildren) {
  return (
    <StarknetConfig
      autoConnect
      chains={[sepolia]}
      connectors={connectors}
      explorer={starkscan}
      provider={provider}
    >
      {children}
    </StarknetConfig>
  );
}

const url =
  !import.meta.env.NEXT_PUBLIC_VERCEL_BRANCH_URL ||
  import.meta.env.NEXT_PUBLIC_VERCEL_BRANCH_URL.split(".")[0] ===
    "cartridge-starknet-react-next"
    ? import.meta.env.VITE_XFRAME_URL
    : "https://" +
      (import.meta.env.NEXT_PUBLIC_VERCEL_BRANCH_URL ?? "").replace(
        "cartridge-starknet-react-next",
        "keychain"
      );

function provider(chain: Chain) {
  switch (chain) {
    case mainnet:
      return new RpcProvider({
        nodeUrl: import.meta.env.VITE_RPC_MAINNET,
      });
    case sepolia:
    default:
      return new RpcProvider({
        nodeUrl: import.meta.env.VITE_RPC_SEPOLIA,
      });
  }
}

const ETH_TOKEN_ADDRESS =
  "0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7";
// const PAPER_TOKEN_ADDRESS =
//   "0x0410466536b5ae074f7fea81e5533b8134a9fa08b3dd077dd9db08f64997d113";

const DOJO_FREN_ADDRESS =
  "0x2d83f954ec3e284017d3b7f4a818c8d00343787c6b537bd882b480a1ab72b99";

const connectors = [
  new CartridgeConnector(
    [
      {
        target: ETH_TOKEN_ADDRESS,
        method: "approve",
        description:
          "Lorem Ipsum is simply dummy text of the printing and typesetting industry.",
      },
      {
        target: ETH_TOKEN_ADDRESS,
        method: "transfer",
      },
      {
        target: DOJO_FREN_ADDRESS,
        method: "play_game",
      },
      {
        target: DOJO_FREN_ADDRESS,
        method: "spawn_fren",
      },
      {
        target: DOJO_FREN_ADDRESS,
        method: "secret",
      },
    ],
    {
      url,
      rpc: import.meta.env.VITE_RPC_SEPOLIA,
      paymaster: {
        caller: shortString.encodeShortString("ANY_CALLER"),
      },
      // theme: "dope-wars",
      // colorMode: "light"
      // prefunds: [
      //   {
      //     address: ETH_TOKEN_ADDRESS,
      //     min: "300000000000000",
      //   },
      //   // {
      //   //   address: PAPER_TOKEN_ADDRESS,
      //   //   min: "100",
      //   // },
      // ],
    }
  ) as never as Connector,
];
