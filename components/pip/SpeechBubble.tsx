"use client";

import type { CSSProperties, ReactNode } from "react";
import { motion, useReducedMotion } from "framer-motion";

type Tail = "left" | "right" | "bottom";

interface SpeechBubbleProps {
  children: ReactNode;
  tail?: Tail;
  className?: string;
}

const SHADOW = "drop-shadow(0 6px 14px rgba(74, 42, 23, 0.12)) drop-shadow(0 1px 2px rgba(74, 42, 23, 0.08))";

/** Where the bubble grows from, so the pop-in starts at the speaker. */
const ORIGIN: Record<Tail, string> = {
  left: "0% 60%",
  right: "100% 60%",
  bottom: "50% 100%",
};

/** Tail placement just outside the bubble edge. */
const TAIL_STYLE: Record<Tail, CSSProperties> = {
  left: { left: -15, top: "60%", width: 20, height: 26, transform: "translateY(-50%)" },
  right: { right: -15, top: "60%", width: 20, height: 26, transform: "translateY(-50%) scaleX(-1)" },
  bottom: { bottom: -15, left: "50%", width: 26, height: 20, transform: "translateX(-50%)" },
};

function TailShape({ tail }: { tail: Tail }) {
  if (tail === "bottom") {
    return (
      <svg viewBox="0 0 26 20" aria-hidden="true" className="absolute block" style={TAIL_STYLE.bottom}>
        <path d="M0 0 H26 C20 4 16 10 14 19 C13.4 20.4 12.6 20.4 12 19 C10 10 6 4 0 0 Z" fill="#FFFFFF" />
      </svg>
    );
  }
  // Drawn pointing left; the right tail is the same shape mirrored.
  return (
    <svg viewBox="0 0 20 26" aria-hidden="true" className="absolute block" style={TAIL_STYLE[tail]}>
      <path d="M20 0 V26 C16 20 10 16 1 14 C-0.4 13.4 -0.4 12.6 1 12 C10 10 16 6 20 0 Z" fill="#FFFFFF" />
    </svg>
  );
}

export default function SpeechBubble({ children, tail = "left", className }: SpeechBubbleProps) {
  const reduce = useReducedMotion() ?? false;

  return (
    <motion.div
      className={["relative inline-block max-w-full", className].filter(Boolean).join(" ")}
      style={{ filter: SHADOW, transformOrigin: ORIGIN[tail] }}
      initial={reduce ? { opacity: 0 } : { opacity: 0, scale: 0.8, y: 6 }}
      animate={reduce ? { opacity: 1 } : { opacity: 1, scale: 1, y: 0 }}
      transition={
        reduce
          ? { duration: 0.2 }
          : { type: "spring", stiffness: 420, damping: 24, opacity: { duration: 0.15 } }
      }
    >
      <div className="relative rounded-[24px] bg-white px-6 py-4 text-lg leading-snug text-stone-800">
        {children}
      </div>
      <TailShape tail={tail} />
    </motion.div>
  );
}
