import { Canvas } from '@react-three/fiber';
import { Environment, OrthographicCamera } from '@react-three/drei';
import HandVisualizer from './HandVisualizer';
import SurgicalTool from './SurgicalTool';

const Scene = ({ landmarksRef }) => {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 1 }}>
      <Canvas
        style={{ position: 'absolute', inset: 0 }}
        gl={{ alpha: true, antialias: true }}
        onCreated={({ gl }) => {
          gl.setClearColor('#000000', 0);
        }}
      >
        <OrthographicCamera makeDefault position={[0, 0, 10]} zoom={50} />
        
        <ambientLight intensity={0.5} />
        <directionalLight position={[10, 10, 5]} intensity={1} />

        {/* Image-based lighting for nicer shading (keeps webcam visible). */}
        <Environment preset="studio" background={false} />
        
        <HandVisualizer landmarksRef={landmarksRef} />
        <SurgicalTool landmarksRef={landmarksRef} />
      </Canvas>
    </div>
  );
};

export default Scene;
