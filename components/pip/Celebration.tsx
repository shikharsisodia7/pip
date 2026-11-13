"use client";

import { useEffect } from "react";

interface CelebrationProps {
  fire: boolean | number;
}

const COLORS = ["#F6A12E", "#E5792B", "#FFC23D", "#F28B74", "#C47A3F", "#FFD166"];
const DURATION_MS = 1200;

/**
 * Fires a short two-sided confetti burst whenever `fire` becomes truthy or
 * changes to a new number. Renders nothing; canvas-confetti draws on its own
 * fixed, pointer-events-free canvas.
 */
export default function Celebration({ fire }: CelebrationProps) {
  useEffect(() => {
    if (!fire || typeof window === "undefined") return;

    let cancelled = false;
    let frame = 0;

    void import("canvas-confetti").then(({ default: confetti }) => {
      if (cancelled) return;

      const shared = {
        colors: COLORS,
        particleCount: 3,
        spread: 58,
        startVelocity: 52,
        gravity: 1.05,
        ticks: 220,
        scalar: 0.95,
        shapes: ["circle", "square"] as ("circle" | "square")[],
        disableForReducedMotion: true,
        zIndex: 60,
      };

      // A fuller opening pop from each side, then a short stream.
      confetti({ ...shared, particleCount: 26, angle: 60, origin: { x: 0, y: 0.75 } });
      confetti({ ...shared, particleCount: 26, angle: 120, origin: { x: 1, y: 0.75 } });

      const end = performance.now() + DURATION_MS;
      let tick = 0;
      const stream = () => {
        if (cancelled || performance.now() > end) return;
        if (tick++ % 3 === 0) {
          confetti({ ...shared, angle: 60, origin: { x: 0, y: 0.75 } });
          confetti({ ...shared, angle: 120, origin: { x: 1, y: 0.75 } });
        }
        frame = requestAnimationFrame(stream);
      };
      frame = requestAnimationFrame(stream);
    });

    return () => {
      // Particles already in flight finish on their own; only the stream stops.
      cancelled = true;
      cancelAnimationFrame(frame);
    };
  }, [fire]);

  return null;
}
