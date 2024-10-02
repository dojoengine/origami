
import "./App.css";
import { StarknetProvider } from "./components/StarknetProvider";
import { ConnectWallet } from "./components/ConnectWallet";
import Quests from "./components/quests";

function App() {
  return (
    <StarknetProvider>
      <ConnectWallet />
      <div>---------------</div>
      <Quests />
    </StarknetProvider>
  );
}

export default App;
