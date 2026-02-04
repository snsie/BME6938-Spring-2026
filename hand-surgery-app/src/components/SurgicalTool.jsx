import { useRef, useState } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';

const SurgicalTool = ({ landmarksRef }) => {
  const meshRef = useRef();
  const [color, setColor] = useState("cyan");
  const { viewport } = useThree();

  // Position the tool in the center or slightly off-center
  // Using a fixed position for the tool
  const toolPosition = new THREE.Vector3(0, 0, 0);

  useFrame(() => {
    if (!landmarksRef.current || landmarksRef.current.length === 0) return;

    // Check all detected hands
    let isTouching = false;
    
    for (const hand of landmarksRef.current) {
        // Landmark 8 is the Index Finger Tip
        const indexTip = hand[8];
        
        // Map normalized coordinates (0..1) to viewport coordinates
        // x: (0..1) -> (-width/2 .. width/2)
        // y: (0..1) -> (height/2 .. -height/2)  <-- Note Y flip
        const x = (indexTip.x - 0.5) * -viewport.width; // Flip X for mirror effect
        const y = (indexTip.y - 0.5) * -viewport.height;
        const z = 0; // Assume interaction on z=0 plane for simplicity

        const fingerPos = new THREE.Vector3(x, y, z);
        
        // Simple distance check
        // Tool radius is roughly 1 (geometry args)
        if (fingerPos.distanceTo(toolPosition) < 1.5) {
            isTouching = true;
        }
    }

    if (isTouching) {
        setColor("hotpink");
        // Simple interaction: rotate the tool when touched
        meshRef.current.rotation.x += 0.05;
        meshRef.current.rotation.y += 0.05;
    } else {
        setColor("cyan");
    }
  });

  return (
    <mesh ref={meshRef} position={toolPosition}>
      {/* A cylinder acting as a handle/tool */}
      <cylinderGeometry args={[0.2, 0.2, 3, 32]} />
      <meshStandardMaterial color={color} />
    </mesh>
  );
};

export default SurgicalTool;
