import { BurnerAccount, useBurnerManager } from "@dojoengine/create-burner";
import { ReactNode, createContext, useContext, useMemo } from "react";
import { Account } from "starknet";
import { SetupResult } from "./generated/setup";

export interface DojoContextType extends SetupResult {}

export const DojoContext = createContext<DojoContextType | null>(null);

export const DojoProvider = ({
  children,
  value,
}: {
  children: ReactNode;
  value: SetupResult;
}) => {
  const currentValue = useContext(DojoContext);
  if (currentValue) throw new Error("DojoProvider can only be used once");

  return (
    <DojoContext.Provider
      value={{
        ...value,
      }}
    >
      {children}
    </DojoContext.Provider>
  );
};
