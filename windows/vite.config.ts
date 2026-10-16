import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

/* The UI reads the Mac's data files (themes, kits) in place, so the dev server may serve the repo root. */
const repoRoot = fileURLToPath(new URL("..", import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@mac": `${repoRoot}Sources/TabbiKitCore`,
      "@shared": `${repoRoot}shared`,
      "@backend": `${repoRoot}backend`,
    },
  },
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    fs: { allow: [repoRoot] },
    watch: { ignored: ["**/src-tauri/**"] },
  },
  build: {
    target: "chrome120",
    outDir: "dist",
    emptyOutDir: true,
    /* The kit gallery builds too, so a broken gallery fails the build instead of only the snapshot run. */
    rollupOptions: { input: { main: "index.html", gallery: "gallery.html" } },
    /*
     * Vite's 500 kB warning is for pages fetched over a network. Tabbi loads
     * its bundle from disk, and most of it is the pet art the closed pill
     * draws at once, so splitting it off would only delay the first frame.
     * The limit still catches a bundle that grows by surprise.
     */
    chunkSizeWarningLimit: 800,
  },
});
