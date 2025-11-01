// === Vanswap WalletConnect + Web3Modal v2 ===
// Project ID: 6af5ba798c7f845b37698f9d8b1380cb

const projectId = "6af5ba798c7f845b37698f9d8b1380cb";

let modal, provider;

async function initWeb3Modal() {
  const { Web3Modal } = window["web3modal-html"];
  const { EthereumClient, modalConnectors, walletConnectProvider } = window["web3modal-html"];

  // Inisialisasi Web3Modal
  modal = new Web3Modal({
    projectId,
    themeMode: "dark",
    walletImages: {},
  });
}

async function connectWallet() {
  try {
    // Buka modal WalletConnect
    const session = await modal.openModal();
    console.log("✅ Wallet terhubung:", session);
    document.getElementById("status").innerHTML = `
      <p>✅ Wallet Connected!</p>
      <code>${JSON.stringify(session, null, 2)}</code>
    `;
  } catch (err) {
    console.error("❌ Gagal koneksi:", err);
    document.getElementById("status").textContent = "Koneksi wallet dibatalkan.";
  }
}

document.addEventListener("DOMContentLoaded", () => {
  const btn = document.getElementById("connectBtn");
  if (btn) {
    btn.addEventListener("click", async () => {
      document.getElementById("status").textContent = "Menyiapkan WalletConnect...";
      await initWeb3Modal();
      await connectWallet();
    });
  }
});
