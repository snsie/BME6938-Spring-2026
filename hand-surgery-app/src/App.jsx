import { useRef, useState } from 'react';
import HandManager from './components/HandManager';
import Scene from './components/Scene';
import './App.css';

function App() {
  const landmarksRef = useRef([]);
  const [status, setStatus] = useState("Initializing...");

  return (
    <div style={{ position: 'relative', width: '100vw', height: '100vh', overflow: 'hidden', backgroundColor: 'black' }}>
      <HandManager landmarksRef={landmarksRef} onStatusChange={setStatus} />
      <Scene landmarksRef={landmarksRef} />
      <div style={{
        position: 'absolute',
        top: '20px',
        left: '20px',
        zIndex: 2,
        color: 'white',
        backgroundColor: 'rgba(0,0,0,0.5)',
        padding: '10px',
        borderRadius: '5px',
        pointerEvents: 'none'
      }}>
        <h1>Virtual Surgery</h1>
        <p>Status: <strong>{status}</strong></p>
        <p>Allow camera access. Raise your hand.</p>
        <p>Touch the cyan cylinder with your index finger to interact.</p>
      </div>
    </div>
  );
}

export default App;
