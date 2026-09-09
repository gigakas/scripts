<template>
  <div id="app">
    <h1>3D Cube with Vue and Three.js</h1>
    <div ref="canvasContainer" style="width: 100%; height: 500px;"></div>
  </div>
</template>

<script>
import * as THREE from 'three'
import { onMounted, ref } from 'vue'

export default {
  name: 'App',
  setup() {
    const canvasContainer = ref(null)
    
    onMounted(() => {
      // Scene setup
      const scene = new THREE.Scene()
      
      // Camera setup
      const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000)
      camera.position.z = 5
      
      // Renderer setup
      const renderer = new THREE.WebGLRenderer({ antialias: true })
      renderer.setSize(canvasContainer.value.offsetWidth, canvasContainer.value.offsetHeight)
      canvasContainer.value.appendChild(renderer.domElement)
      
      // Create cube geometry and material
      const geometry = new THREE.BoxGeometry()
      const material = new THREE.MeshBasicMaterial({ 
        color: 0x00ff00,
        wireframe: true
      })
      
      // Create cube mesh
      const cube = new THREE.Mesh(geometry, material)
      scene.add(cube)
      
      // Add lighting
      const ambientLight = new THREE.AmbientLight(0xffffff, 0.5)
      scene.add(ambientLight)
      
      const directionalLight = new THREE.DirectionalLight(0xffffff, 0.5)
      directionalLight.position.set(1, 1, 1)
      scene.add(directionalLight)
      
      // Animation loop
      const animate = () => {
        requestAnimationFrame(animate)
        
        // Rotate cube
        cube.rotation.x += 0.01
        cube.rotation.y += 0.01
        
        renderer.render(scene, camera)
      }
      
      animate()
      
      // Handle window resize
      const handleResize = () => {
        camera.aspect = canvasContainer.value.offsetWidth / canvasContainer.value.offsetHeight
        camera.updateProjectionMatrix()
        renderer.setSize(canvasContainer.value.offsetWidth, canvasContainer.value.offsetHeight)
      }
      
      window.addEventListener('resize', handleResize)
      
      // Cleanup
      return () => {
        window.removeEventListener('resize', handleResize)
        if (canvasContainer.value) {
          canvasContainer.value.removeChild(renderer.domElement)
        }
      }
    })
    
    return {
      canvasContainer
    }
  }
}
</script>

<style>
#app {
  font-family: Avenir, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  text-align: center;
  color: #2c3e50;
  margin-top: 60px;
}
</style>