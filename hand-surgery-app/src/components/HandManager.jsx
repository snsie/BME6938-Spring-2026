import { useEffect, useRef, useState } from 'react';
import { FilesetResolver, HandLandmarker } from '@mediapipe/tasks-vision';

const HandManager = ({ landmarksRef, onStatusChange }) => {
  const videoRef = useRef(null);
  const streamRef = useRef(null);
  const lastStatusRef = useRef("");
  const startWebcamRef = useRef(null);
  const [cameraHelp, setCameraHelp] = useState("");
  const [showStartButton, setShowStartButton] = useState(false);

  const updateStatus = (msg) => {
    if (lastStatusRef.current !== msg) {
        console.log(`[Status Update] ${msg}`);
        lastStatusRef.current = msg;
        if (onStatusChange) onStatusChange(msg);
    }
  };

  useEffect(() => {
    let handLandmarker = null;
    let animationFrameId = null;
    let cancelled = false;

    const getSecureContextHelp = () => {
      if (typeof window === 'undefined') return "";
      if (window.isSecureContext) return "";

      const { protocol, hostname } = window.location;
      // getUserMedia generally requires a secure context: https:// or http://localhost
      return `Camera requires a secure context (HTTPS). Current origin is ${protocol}//${hostname}. If you opened the built app from a file (file://) or plain HTTP, use \\"npm run preview\\" or deploy over HTTPS.`;
    };

    const getUserMediaAvailabilityHelp = () => {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        return "Browser API navigator.mediaDevices.getUserMedia not available.";
      }
      return "";
    };

    const setupMediaPipe = async () => {
      try {
        updateStatus("Loading MediaPipe (WASM)...");
        const vision = await FilesetResolver.forVisionTasks(
          // Keep this in sync with package.json @mediapipe/tasks-vision.
          "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm"
        );

        if (cancelled) return;
        
        updateStatus("Loading Hand Model...");
        // Try CPU first for better compatibility in Codespaces/VMs
        handLandmarker = await HandLandmarker.createFromOptions(vision, {
          baseOptions: {
            modelAssetPath: "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task",
            delegate: "CPU" 
          },
          runningMode: "VIDEO",
          numHands: 2,
          minHandDetectionConfidence: 0.5,
          minHandPresenceConfidence: 0.5,
          minTrackingConfidence: 0.5
        });

        if (cancelled) {
          handLandmarker.close();
          return;
        }

        updateStatus("Model Ready. Requesting Camera...");
        await startWebcam();
      } catch (error) {
        console.error("MediaPipe Limit/Error:", error);
        updateStatus("AI Init Error: " + error.message);
      }
    };

    const startWebcam = async () => {
      try {
        setShowStartButton(false);
        setCameraHelp("");

        const secureHelp = getSecureContextHelp();
        if (secureHelp) {
          updateStatus("Camera Error: insecure context");
          setCameraHelp(secureHelp);
          return;
        }

        const availabilityHelp = getUserMediaAvailabilityHelp();
        if (availabilityHelp) {
          updateStatus("Camera Error: unsupported browser");
          setCameraHelp(availabilityHelp);
          return;
        }

        // Explicitly ask for 1280x720, but accept whatever
        const constraints = {
            video: {
                width: { ideal: 1280 },
                height: { ideal: 720 },
                facingMode: "user"
            }
        };

        const stream = await navigator.mediaDevices.getUserMedia(constraints);
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }

        // Keep our own reference so StrictMode cleanup can always stop the camera,
        // even if the <video> ref is temporarily null.
        streamRef.current = stream;
        
        if (videoRef.current) {
          const videoEl = videoRef.current;
          videoEl.srcObject = stream;

          // Wait for metadata to load so dimensions are known.
          videoEl.onloadedmetadata = async () => {
            try {
              if (cancelled) return;
              // Some browsers require muted for autoplay to succeed.
              await videoEl.play();
              if (cancelled) return;
              updateStatus("Camera Active. Processing...");
              predictWebcam();
            } catch (playErr) {
              console.error("Video play() failed:", playErr);
              updateStatus("Camera Error: autoplay blocked");
              setCameraHelp("Your browser blocked video autoplay. Click 'Start Camera' to begin.");
              setShowStartButton(true);
            }
          };
        } else {
          updateStatus("Camera Error: video element not ready");
        }
      } catch (err) {
        console.error("Camera Error:", err);

        const name = err?.name || "CameraError";
        let help = err?.message || "";
        if (name === 'NotAllowedError') {
          help = window?.isSecureContext
            ? "Permission denied. Allow camera access in the browser permission prompt/settings, then click 'Start Camera'."
            : (getSecureContextHelp() || "Camera permission denied.");
        } else if (name === 'NotFoundError' || name === 'DevicesNotFoundError') {
          help = "No camera device found.";
        } else if (name === 'NotReadableError' || name === 'TrackStartError') {
          help = "Camera is already in use by another app/tab.";
        } else if (name === 'SecurityError') {
          help = getSecureContextHelp() || "Security error accessing camera.";
        }

        updateStatus("Camera Error: " + name);
        if (help) setCameraHelp(help);
        setShowStartButton(true);
      }
    };

    startWebcamRef.current = startWebcam;

    const predictWebcam = () => {
      // Loop
      animationFrameId = requestAnimationFrame(predictWebcam);

      if (handLandmarker && videoRef.current && videoRef.current.readyState >= 2) {
        let startTimeMs = performance.now();
        try {
            const results = handLandmarker.detectForVideo(videoRef.current, startTimeMs);
            
            if (results.landmarks) {
                landmarksRef.current = results.landmarks;
                if (results.landmarks.length > 0) {
                     updateStatus(`Tracking ${results.landmarks.length} Hand(s)`);
                } else {
                     // Keep status as "Processing" or similar to avoid flickering
                     // updateStatus("Camera Active. No Hands."); 
                }
            }
        } catch (e) {
            console.warn("Prediction error:", e);
        }
      }
    };

    setupMediaPipe();

    return () => {
      cancelled = true;
      if (animationFrameId) cancelAnimationFrame(animationFrameId);
      if (handLandmarker) handLandmarker.close();

      startWebcamRef.current = null;

      const stream = streamRef.current || (videoRef.current ? videoRef.current.srcObject : null);
      if (stream && stream.getTracks) {
        stream.getTracks().forEach((t) => t.stop());
      }
      streamRef.current = null;

      if (videoRef.current) {
        videoRef.current.onloadedmetadata = null;
        videoRef.current.srcObject = null;
      }
    };
  }, [landmarksRef]);

  return (
    <div style={{ 
        position: 'absolute', 
        top: 0, 
        left: 0, 
        width: '100%', 
        height: '100%', 
        zIndex: 0,
        overflow: 'hidden',
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center'
    }}>
      {/* Video visible for debugging, flipped for mirror effect */}
      <video 
        ref={videoRef} 
        style={{ 
            minWidth: '100%', 
            minHeight: '100%', 
            objectFit: 'cover',
            transform: 'scaleX(-1)', // Mirror effect
            opacity: 1
        }} 
        autoPlay 
        muted
        playsInline
      ></video>

      {(cameraHelp || showStartButton) && (
        <div
          style={{
            position: 'absolute',
            top: 20,
            right: 20,
            zIndex: 3,
            maxWidth: 420,
            color: 'white',
            background: 'rgba(0,0,0,0.65)',
            padding: 12,
            borderRadius: 8,
            pointerEvents: 'auto',
            fontSize: 14,
            lineHeight: 1.3,
          }}
        >
          {cameraHelp && <div style={{ marginBottom: showStartButton ? 10 : 0 }}>{cameraHelp}</div>}
          {showStartButton && (
            <button
              onClick={() => startWebcamRef.current && startWebcamRef.current()}
              style={{
                cursor: 'pointer',
                padding: '8px 10px',
                borderRadius: 6,
                border: '1px solid rgba(255,255,255,0.25)',
                background: 'rgba(0, 180, 255, 0.25)',
                color: 'white',
              }}
            >
              Start Camera
            </button>
          )}
        </div>
      )}
    </div>
  );
};

export default HandManager;
