// === Vanswap WalletConnect v2 Integration ===
// Project ID: 6af5ba798c7f845b37698f9d8b1380cb

let client;

async function initWalletConnect() {
  try {
    client = await window.WalletConnectSignClient.default.init({
      projectId: "6af5ba798c7f845b37698f9d8b1380cb",
      relayUrl: "wss://relay.walletconnect.com",
      metadata: {
        name: "Vanswap DEX",
        description: "Vanswap DApp with WalletConnect v2",
        url: window.location.origin,
        icons: ["https://raw.githubusercontent.com/username/vanswap/main/logo.png"],
      },
    });
    console.log("✅ WalletConnect client initialized!");
  } catch (err) {
    console.error("❌ Gagal inisialisasi WalletConnect:", err);
    document.getElementById("status").textContent = "Gagal memuat WalletConnect.";
  }
}

async function connectWallet() {
  if (!client) {
    await initWalletConnect();
  }

  try {
    const { uri, approval } = await client.connect({
      requiredNamespaces: {
        eip155: {
          methods: ["eth_sendTransaction", "personal_sign"],
          chains: ["eip155:56"], // Binance Smart Chain
          events: ["chainChanged", "accountsChanged"],
        },
      },
    });

    // Jika WalletConnect menghasilkan URI (belum ada session)
    if (uri) {
      console.log("Scan QR dengan wallet kamu:", uri);
      document.getElementById("status").innerHTML = `
        <p>📱 Scan QR Code ini dari wallet kamu (MetaMask, OKX, Trust, dsb):</p>
        <textarea readonly style="width:90%;height:80px;">${uri}</textarea>
        <p>Atau klik link ini: <a href="wc:${uri}" style="color:#00c3ff">Hubungkan Wallet</a></p>
      `;
    }

    // Tunggu approval (user menyetujui koneksi di wallet)
    const session = await approval();

    const account = session.namespaces.eip155.accounts[0];
    console.log("✅ Connected account:", account);

    document.getElementById("status").innerHTML = `
      <p>✅ Wallet terhubung:</p>
      <code>${account}</code>
    `;
  } catch (err) {
    console.error("❌ Error connectWallet:", err);
    document.getElementById("status").textContent = "Koneksi wallet gagal.";
  }
}

// Jalankan saat tombol connect diklik
document.addEventListener("DOMContentLoaded", () => {
  const connectBtn = document.getElementById("connectBtn");
  if (connectBtn) {
    connectBtn.addEventListener("click", async () => {
      document.getElementById("status").textContent = "Menghubungkan ke wallet...";
      await connectWallet();
    });
  } else {
    console.warn("⚠️ Tombol #connectBtn tidak ditemukan di halaman.");
  }
});
