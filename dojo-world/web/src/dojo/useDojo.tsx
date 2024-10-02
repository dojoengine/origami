import { useContext } from "react";
import { DojoContext, DojoContextType} from "./DojoContext";

export const useDojo = () => {
    const context = useContext(DojoContext);
    if (!context)
        throw new Error(
            "The `useDojo` hook must be used within a `DojoProvider`"
        );

    return {
        setup: context,
    };
};
