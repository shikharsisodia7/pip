// The product is the iPhone app in ios/. This server hosts its API under /api.
export default function Home() {
  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', padding: 32, maxWidth: 560 }}>
      <h1>Pip Reads It Wrong</h1>
      <p>This server hosts the API for the Pip iPhone app. The app lives in the ios folder of this repository.</p>
    </main>
  );
}
