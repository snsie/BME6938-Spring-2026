import { useRef, useMemo } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';

// Standard MediaPipe hand connections
const CONNECTIONS = [
  [0, 1], [1, 2], [2, 3], [3, 4], // Thumb
  [0, 5], [5, 6], [6, 7], [7, 8], // Index
  [0, 9], [9, 10], [10, 11], [11, 12], // Middle
  [0, 13], [13, 14], [14, 15], [15, 16], // Ring
  [0, 17], [17, 18], [18, 19], [19, 20] // Pinky
];

const HandVisualizer = ({ landmarksRef }) => {
  const jointMeshRef = useRef();
  const boneMeshRef = useRef();
  const { viewport } = useThree();
  
  // Reusable objects to avoid garbage collection in the render loop
  const dummy = useMemo(() => new THREE.Object3D(), []);
  const vecA = useMemo(() => new THREE.Vector3(), []);
  const vecB = useMemo(() => new THREE.Vector3(), []);
  const up = useMemo(() => new THREE.Vector3(0, 1, 0), []); 

  useFrame(() => {
    if (!jointMeshRef.current || !boneMeshRef.current) return;
    
    const landmarks = landmarksRef.current || [];
    
    // Support up to 2 hands, 21 joints, 20 bones per hand
    const MAX_HANDS = 2;
    const JOINTS_PER_HAND = 21;
    const BONES_PER_HAND = CONNECTIONS.length; 
    
    let jointIndex = 0;
    let boneIndex = 0;

    // Helper: Map MediaPipe normalized coords (0..1) to 3D world coords
    const updateVec3FromLandmark = (lm, targetVec) => {
        // x: 0..1 -> -width/2 .. width/2 (flipped because webcam is mirrored or standard mirrored coordinate space)
        const x = (lm.x - 0.5) * -viewport.width;
        // y: 0..1 (top to bottom) -> height/2 .. -height/2
        const y = (lm.y - 0.5) * -viewport.height;
        // z: Relative depth. Scaling by 5 to make it perceptible in 3D space
        const z = -lm.z * 5; 
        targetVec.set(x, y, z);
    };

    for (let i = 0; i < MAX_HANDS; i++) {
        const hand = landmarks[i];
        
        if (hand) {
            // Debug log once per second-ish (throttled by random chance for simplicity or just once)
            if (Math.random() < 0.01) console.log("Rendering Hand:", hand[0]);

            // 1. Render Joints (Spheres)
            hand.forEach((point) => {
                updateVec3FromLandmark(point, vecA);
                
                dummy.position.copy(vecA);
                dummy.rotation.set(0, 0, 0); // Reset rotation
                dummy.scale.set(1, 1, 1);
                dummy.updateMatrix();
                
                jointMeshRef.current.setMatrixAt(jointIndex++, dummy.matrix);
            });

            // 2. Render Bones (Cylinders)
            CONNECTIONS.forEach(([startIdx, endIdx]) => {
                const startLm = hand[startIdx];
                const endLm = hand[endIdx];

                if (startLm && endLm) {
                    updateVec3FromLandmark(startLm, vecA);
                    updateVec3FromLandmark(endLm, vecB);

                    const dist = vecA.distanceTo(vecB);
                    
                    // Position: Midpoint between A and B
                    // dummy.position = (A + B) / 2
                    dummy.position.copy(vecA).add(vecB).multiplyScalar(0.5);
                    
                    // Orientation: Rotate Y-up cylinder to point from A to B
                    // Direction Vector = normalize(B - A)
                    // We clone vecB so we don't destroy it immediately if needed, 
                    // though here we are done with vecB's position value.
                    const dir = vecB.clone().sub(vecA).normalize();
                    dummy.quaternion.setFromUnitVectors(up, dir);
                    
                    // Scale: Height = distance. Keep X/Z scale as 1 (relative to geometry radius)
                    dummy.scale.set(1, dist, 1);
                    
                    dummy.updateMatrix();
                    boneMeshRef.current.setMatrixAt(boneIndex++, dummy.matrix);
                }
            });
        }
    }

    // Hide unused joints
    const totalMaxJoints = MAX_HANDS * JOINTS_PER_HAND;
    for (let i = jointIndex; i < totalMaxJoints; i++) {
        dummy.position.set(0, 0, 1000); // Move far away
        dummy.scale.set(0, 0, 0);
        dummy.updateMatrix();
        jointMeshRef.current.setMatrixAt(i, dummy.matrix);
    }

    // Hide unused bones
    const totalMaxBones = MAX_HANDS * BONES_PER_HAND;
    for (let i = boneIndex; i < totalMaxBones; i++) {
        dummy.position.set(0, 0, 1000);
        dummy.scale.set(0, 0, 0);
        dummy.updateMatrix();
        boneMeshRef.current.setMatrixAt(i, dummy.matrix);
    }

    // Mark as needing update for Three.js to re-render the instances
    jointMeshRef.current.instanceMatrix.needsUpdate = true;
    boneMeshRef.current.instanceMatrix.needsUpdate = true;
  });

  return (
    <group>
        {/* Instanced Mesh for Joints (Spheres) */}
        {/* Increased geometry size for better visibility */}
        <instancedMesh ref={jointMeshRef} args={[null, null, 42]} frustumCulled={false}>
          <sphereGeometry args={[0.6, 16, 16]} />
          <meshBasicMaterial color="#FF2D55" depthTest={false} depthWrite={false} />
        </instancedMesh>
        
        {/* Instanced Mesh for Bones (Cylinders) */}
        <instancedMesh ref={boneMeshRef} args={[null, null, 40]} frustumCulled={false}>
          <cylinderGeometry args={[0.25, 0.25, 1, 12]} />
          <meshBasicMaterial color="#FFFFFF" depthTest={false} depthWrite={false} />
        </instancedMesh>
    </group>
  );
};

export default HandVisualizer;
