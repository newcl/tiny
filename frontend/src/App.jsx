import { useMemo, useState } from "react";

const initialPayload = {
  type: "email",
  to: "user@example.com",
  subject: "Hello from tiny"
};

function App() {
  const [apiBase, setApiBase] = useState("http://127.0.0.1:8080");
  const [payloadText, setPayloadText] = useState(JSON.stringify(initialPayload, null, 2));
  const [priority, setPriority] = useState("1024");
  const [delaySeconds, setDelaySeconds] = useState("0");
  const [ttrSeconds, setTtrSeconds] = useState("30");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [result, setResult] = useState("");

  const endpoint = useMemo(() => {
    const p = new URLSearchParams();
    if (priority !== "") p.set("priority", priority);
    if (delaySeconds !== "") p.set("delay_seconds", delaySeconds);
    if (ttrSeconds !== "") p.set("ttr_seconds", ttrSeconds);
    const query = p.toString();
    return `${apiBase.replace(/\/$/, "")}/jobs${query ? `?${query}` : ""}`;
  }, [apiBase, priority, delaySeconds, ttrSeconds]);

  async function onSubmit(e) {
    e.preventDefault();
    setResult("");

    let parsed;
    try {
      parsed = JSON.parse(payloadText);
    } catch {
      setResult("Payload must be valid JSON.");
      return;
    }

    setIsSubmitting(true);
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(parsed)
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setResult(`Error ${res.status}: ${data.error || "Request failed"}`);
        return;
      }
      setResult(`Queued job ${data.job_id} in tube ${data.tube}`);
    } catch (err) {
      setResult(`Network error: ${err.message}`);
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="app-shell">
      <section className="panel">
        <h1>Tiny Queue Console</h1>
        <p className="hint">Submit JSON jobs into beanstalkd via your Go API.</p>

        <form onSubmit={onSubmit} className="stack">
          <label>
            API Base URL
            <input value={apiBase} onChange={(e) => setApiBase(e.target.value)} placeholder="http://127.0.0.1:8080" />
          </label>

          <div className="row">
            <label>
              Priority
              <input value={priority} onChange={(e) => setPriority(e.target.value)} />
            </label>
            <label>
              Delay Seconds
              <input value={delaySeconds} onChange={(e) => setDelaySeconds(e.target.value)} />
            </label>
            <label>
              TTR Seconds
              <input value={ttrSeconds} onChange={(e) => setTtrSeconds(e.target.value)} />
            </label>
          </div>

          <label>
            Job Payload JSON
            <textarea value={payloadText} onChange={(e) => setPayloadText(e.target.value)} rows={12} />
          </label>

          <div className="endpoint">POST {endpoint}</div>

          <button type="submit" disabled={isSubmitting}>
            {isSubmitting ? "Submitting..." : "Submit Job"}
          </button>
        </form>

        {result && <pre className="result">{result}</pre>}
      </section>
    </main>
  );
}

export default App;
