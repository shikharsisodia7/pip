"use client";

import { useEffect, useId, useState } from "react";
import {
  motion,
  useReducedMotion,
  type MotionStyle,
  type TargetAndTransition,
  type Transition,
  type Variants,
} from "framer-motion";

export type OwlState =
  | "idle"
  | "listening"
  | "speaking"
  | "confused"
  | "thinking"
  | "celebrating";

export interface OwlProps {
  state?: OwlState;
  size?: number;
  className?: string;
}

/* -------------------------------------------------------------------------- */
/* Palette                                                                    */
/* -------------------------------------------------------------------------- */

const C = {
  outline: "#4A2A17",
  body: "#C47A3F",
  bodyShade: "#A9612E",
  wing: "#9A562A",
  wingLight: "#B46B35",
  tuft: "#8F4F26",
  face: "#F9E0B9",
  belly: "#FDEED7",
  bellyMark: "#E8C799",
  eyeWhite: "#FFFFFF",
  iris: "#8A4A22",
  pupil: "#2A1910",
  lid: "#E9BE86",
  beak: "#F6A12E",
  beakShade: "#DB7B17",
  mouth: "#7A2E1C",
  tongue: "#F07F6C",
  feet: "#F6A12E",
  cheek: "#F28B74",
  brow: "#6B3A1E",
  accent: "#E5792B",
  sparkle: "#FFC23D",
  shadow: "#4A2A17",
} as const;

/* -------------------------------------------------------------------------- */
/* Geometry (viewBox is 240 x 240)                                            */
/* -------------------------------------------------------------------------- */

const GROUND_Y = 226;
const NECK = { x: 120, y: 152 };
const EYE_R = 24;
const EYE_L = { x: 93, y: 100 };
const EYE_R_POS = { x: 147, y: 100 };

/** Mirrors local left-side drawing coordinates onto the right side. */
const MIRROR = "matrix(-1 0 0 1 240 0)";

/**
 * Rotation and scale pivots expressed in viewBox units. framer-motion applies
 * CSS transforms to SVG elements, so a view-box transform box lets the origin
 * be given in the same coordinate system the art is drawn in.
 */
function pivot(x: number, y: number): MotionStyle {
  return { transformBox: "view-box", originX: `${x}px`, originY: `${y}px` };
}

/* -------------------------------------------------------------------------- */
/* Animation variants                                                         */
/* -------------------------------------------------------------------------- */

type PoseMap = Record<OwlState, TargetAndTransition>;

const spring: Transition = { type: "spring", stiffness: 260, damping: 18 };
const softSpring: Transition = { type: "spring", stiffness: 160, damping: 14 };
const loop = (duration: number, extra: Transition = {}): Transition => ({
  duration,
  repeat: Infinity,
  ease: "easeInOut",
  ...extra,
});

/**
 * Collapses a looping pose to a still one for reduced motion. Each keyframe
 * list is written so that its first value is the representative resting pose.
 */
function still(pose: TargetAndTransition): TargetAndTransition {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(pose)) {
    if (key === "transition") continue;
    out[key] = Array.isArray(value) ? value[0] : value;
  }
  out.transition = { duration: 0.2 };
  return out as TargetAndTransition;
}

function toVariants(poses: PoseMap, reduce: boolean): Variants {
  const entries = Object.entries(poses).map(([state, pose]) => [
    state,
    reduce ? still(pose) : pose,
  ]);
  return Object.fromEntries(entries) as Variants;
}

const CELEBRATE_HOP = 0.72;

/** Whole character: breathing, speaking bounce, celebration hop. */
const bodyPoses: PoseMap = {
  idle: {
    y: 0,
    scaleY: [1, 1.022, 1],
    scaleX: [1, 0.992, 1],
    transition: { ...loop(3.4), y: spring },
  },
  listening: { y: 0, scaleY: 1, scaleX: 1, transition: spring },
  speaking: {
    y: [0, -5, 0],
    scaleY: [1, 1.02, 1],
    scaleX: 1,
    transition: loop(0.5),
  },
  confused: { y: 0, scaleY: 1, scaleX: 1, transition: spring },
  thinking: { y: 0, scaleY: 1, scaleX: 1, transition: spring },
  celebrating: {
    y: [0, -20, 0, 0],
    scaleY: [1, 1.04, 0.92, 1],
    scaleX: [1, 0.97, 1.07, 1],
    transition: {
      duration: CELEBRATE_HOP,
      times: [0, 0.42, 0.78, 1],
      repeat: Infinity,
      ease: "easeOut",
    },
  },
};

const shadowPoses: PoseMap = {
  idle: { scaleX: 1, opacity: 0.16, transition: spring },
  listening: { scaleX: 1.03, opacity: 0.16, transition: spring },
  speaking: {
    scaleX: [1, 0.94, 1],
    opacity: 0.16,
    transition: loop(0.5),
  },
  confused: { scaleX: 1, opacity: 0.16, transition: spring },
  thinking: { scaleX: 1, opacity: 0.16, transition: spring },
  celebrating: {
    scaleX: [1, 0.68, 1, 1],
    opacity: [0.16, 0.08, 0.16, 0.16],
    transition: {
      duration: CELEBRATE_HOP,
      times: [0, 0.42, 0.78, 1],
      repeat: Infinity,
      ease: "easeOut",
    },
  },
};

/** Head: lean, tilt and small sways around the neck. */
const headPoses: PoseMap = {
  idle: {
    rotate: [0, 2.5, 0, -2.5, 0],
    y: 0,
    scale: 1,
    transition: { ...loop(7), y: spring, scale: spring },
  },
  listening: { rotate: 3, y: 5, scale: 1.045, transition: softSpring },
  speaking: {
    rotate: [0, -2, 0, 2, 0],
    y: 0,
    scale: 1,
    transition: { ...loop(1.8), y: spring, scale: spring },
  },
  confused: {
    rotate: -12,
    y: 1,
    scale: 1,
    transition: { type: "spring", stiffness: 220, damping: 11 },
  },
  thinking: { rotate: -6, y: -1, scale: 1, transition: softSpring },
  celebrating: {
    rotate: [-4, 4, -4],
    y: 0,
    scale: 1.02,
    transition: { ...loop(CELEBRATE_HOP * 2), scale: spring },
  },
};

/** Ear tufts, drawn on the left and mirrored to the right. */
const tuftPoses: PoseMap = {
  idle: {
    rotate: [0, -3, 0],
    scaleY: 1,
    y: 0,
    transition: { ...loop(3.4), scaleY: spring, y: spring },
  },
  listening: { rotate: 12, scaleY: 1.16, y: -3, transition: softSpring },
  speaking: {
    rotate: [0, 4, 0],
    scaleY: 1,
    y: 0,
    transition: { ...loop(0.5), scaleY: spring, y: spring },
  },
  confused: { rotate: 4, scaleY: 0.95, y: 1, transition: softSpring },
  thinking: { rotate: 4, scaleY: 1.04, y: 0, transition: softSpring },
  celebrating: {
    rotate: [8, -4, 8],
    scaleY: 1.12,
    y: -2,
    transition: { ...loop(CELEBRATE_HOP), scaleY: spring, y: spring },
  },
};

/** Wings, drawn on the left and mirrored to the right. */
const wingPoses: PoseMap = {
  idle: { rotate: [0, 4, 0], transition: loop(3.4) },
  listening: { rotate: -4, transition: softSpring },
  speaking: { rotate: [4, 12, 4], transition: loop(1) },
  confused: { rotate: 24, transition: softSpring },
  thinking: { rotate: 6, transition: softSpring },
  celebrating: {
    rotate: [122, 146, 122],
    transition: loop(CELEBRATE_HOP / 2),
  },
};

function browPoses(side: "left" | "right"): PoseMap {
  const s = side === "left" ? 1 : -1;
  return {
    idle: { y: 0, rotate: 0, transition: spring },
    listening: { y: -5, rotate: 0, transition: spring },
    speaking: { y: [-1, -3, -1], rotate: 0, transition: loop(0.5) },
    confused:
      side === "left"
        ? { y: -8, rotate: -10, transition: spring }
        : { y: 2, rotate: -12, transition: spring },
    thinking: { y: -6, rotate: -5 * s, transition: spring },
    celebrating: { y: -8, rotate: 0, transition: spring },
  };
}

/** Where the pupils look, as an offset from the eye center. */
const pupilPoses: PoseMap = {
  idle: {
    x: [0, 0, 3, 3, 0],
    y: [1, 1, 1, 1, 1],
    scale: 1,
    transition: {
      ...loop(8, { times: [0, 0.45, 0.5, 0.85, 0.9] }),
      scale: spring,
    },
  },
  listening: { x: 0, y: 2, scale: 1.12, transition: spring },
  speaking: { x: 0, y: 1, scale: 1, transition: spring },
  confused: { x: -4, y: -1, scale: 0.92, transition: spring },
  thinking: { x: 6, y: -8, scale: 0.95, transition: softSpring },
  celebrating: { x: 0, y: 0, scale: 1, transition: spring },
};

const openEyePoses: PoseMap = {
  idle: { opacity: 1, transition: { duration: 0.15 } },
  listening: { opacity: 1, transition: { duration: 0.15 } },
  speaking: { opacity: 1, transition: { duration: 0.15 } },
  confused: { opacity: 1, transition: { duration: 0.15 } },
  thinking: { opacity: 1, transition: { duration: 0.15 } },
  celebrating: { opacity: 0, transition: { duration: 0.12 } },
};

const happyEyePoses: PoseMap = {
  idle: { opacity: 0, transition: { duration: 0.12 } },
  listening: { opacity: 0, transition: { duration: 0.12 } },
  speaking: { opacity: 0, transition: { duration: 0.12 } },
  confused: { opacity: 0, transition: { duration: 0.12 } },
  thinking: { opacity: 0, transition: { duration: 0.12 } },
  celebrating: { opacity: 1, transition: { duration: 0.15 } },
};

/** Lower beak drop, in viewBox units. Speaking keyframes start open. */
const SPEAK_TIMES = [0, 0.2, 0.45, 0.65, 1];
const lowerBeakPoses: PoseMap = {
  idle: { y: 0, transition: spring },
  listening: { y: 0, transition: spring },
  speaking: {
    y: [11, 0.5, 8, 1.5, 11],
    transition: loop(0.62, { times: SPEAK_TIMES, ease: "easeInOut" }),
  },
  confused: { y: 5, transition: spring },
  thinking: { y: 0, transition: spring },
  celebrating: { y: 12, transition: spring },
};

const mouthPoses: PoseMap = {
  idle: { scaleY: 0, transition: spring },
  listening: { scaleY: 0, transition: spring },
  speaking: {
    scaleY: [1, 0.08, 0.85, 0.15, 1],
    transition: loop(0.62, { times: SPEAK_TIMES, ease: "easeInOut" }),
  },
  confused: { scaleY: 0.4, transition: spring },
  thinking: { scaleY: 0, transition: spring },
  celebrating: { scaleY: 1.1, transition: spring },
};

const cheekPoses: PoseMap = {
  idle: { opacity: 0.42, transition: { duration: 0.3 } },
  listening: { opacity: 0.42, transition: { duration: 0.3 } },
  speaking: { opacity: 0.5, transition: { duration: 0.3 } },
  confused: { opacity: 0.3, transition: { duration: 0.3 } },
  thinking: { opacity: 0.36, transition: { duration: 0.3 } },
  celebrating: { opacity: 0.8, transition: { duration: 0.3 } },
};

function onlyIn(
  active: OwlState,
  shown: TargetAndTransition,
  hidden: TargetAndTransition,
): PoseMap {
  return {
    idle: active === "idle" ? shown : hidden,
    listening: active === "listening" ? shown : hidden,
    speaking: active === "speaking" ? shown : hidden,
    confused: active === "confused" ? shown : hidden,
    thinking: active === "thinking" ? shown : hidden,
    celebrating: active === "celebrating" ? shown : hidden,
  };
}

const questionPoses: PoseMap = onlyIn(
  "confused",
  {
    opacity: 1,
    scale: 1,
    rotate: [0, 10, 0, -6, 0],
    y: 0,
    transition: {
      opacity: { duration: 0.15 },
      scale: { type: "spring", stiffness: 380, damping: 12 },
      y: spring,
      rotate: loop(2.4, { delay: 0.3 }),
    },
  },
  { opacity: 0, scale: 0.3, rotate: 0, y: 8, transition: { duration: 0.15 } },
);

function thoughtDotPoses(index: number): PoseMap {
  return onlyIn(
    "thinking",
    {
      opacity: [1, 0.35, 1],
      scale: [1, 0.8, 1],
      transition: {
        opacity: loop(1.2, { delay: index * 0.2 }),
        scale: loop(1.2, { delay: index * 0.2 }),
      },
    },
    { opacity: 0, scale: 0.4, transition: { duration: 0.15 } },
  );
}

function sparklePoses(index: number): PoseMap {
  return onlyIn(
    "celebrating",
    {
      opacity: [1, 0.55, 1],
      scale: [1, 0.45, 1],
      rotate: [0, 45, 90],
      transition: loop(0.9, { delay: index * 0.17 }),
    },
    { opacity: 0, scale: 0, rotate: 0, transition: { duration: 0.15 } },
  );
}

function buildVariants(reduce: boolean) {
  const v = (poses: PoseMap) => toVariants(poses, reduce);
  return {
    body: v(bodyPoses),
    shadow: v(shadowPoses),
    head: v(headPoses),
    tuft: v(tuftPoses),
    wing: v(wingPoses),
    browLeft: v(browPoses("left")),
    browRight: v(browPoses("right")),
    pupil: v(pupilPoses),
    openEye: v(openEyePoses),
    happyEye: v(happyEyePoses),
    lowerBeak: v(lowerBeakPoses),
    mouth: v(mouthPoses),
    cheek: v(cheekPoses),
    question: v(questionPoses),
    dots: [0, 1, 2].map((i) => v(thoughtDotPoses(i))),
    sparkles: [
      v(sparklePoses(0)),
      v(sparklePoses(1)),
      v(sparklePoses(2)),
      v(sparklePoses(3)),
    ] as const,
  };
}

const MOTION_VARIANTS = buildVariants(false);
const REDUCED_VARIANTS = buildVariants(true);
type OwlVariants = typeof MOTION_VARIANTS;

/* -------------------------------------------------------------------------- */
/* Blinking                                                                   */
/* -------------------------------------------------------------------------- */

/** Toggles true for a brief moment on a random 2.5 to 6 second interval. */
function useBlink(): boolean {
  const [closed, setClosed] = useState(false);

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let cancelled = false;

    const schedule = (delay: number) => {
      timer = setTimeout(() => {
        if (cancelled) return;
        setClosed(true);
        timer = setTimeout(() => {
          if (cancelled) return;
          setClosed(false);
          // Occasionally follow up with a quick second blink.
          const doubleBlink = Math.random() < 0.18;
          schedule(doubleBlink ? 180 : 2500 + Math.random() * 3500);
        }, 130);
      }, delay);
    };

    schedule(1200 + Math.random() * 2500);
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, []);

  return closed;
}

/* -------------------------------------------------------------------------- */
/* Parts                                                                      */
/* -------------------------------------------------------------------------- */

const strokeProps = {
  stroke: C.outline,
  strokeWidth: 3,
  strokeLinejoin: "round" as const,
  strokeLinecap: "round" as const,
};

function Tuft({ variants }: { variants: Variants }) {
  return (
    <motion.g variants={variants} style={pivot(80, 58)}>
      <path
        d="M58 76 C50 62 42 46 36 28 C46 32 54 37 60 42 C60 36 61 31 64 26 C74 34 86 41 98 46 Z"
        fill={C.tuft}
        {...strokeProps}
      />
      <path
        d="M54 56 C50 49 47 43 44 37"
        fill="none"
        stroke={C.wingLight}
        strokeWidth={2.6}
        strokeLinecap="round"
        opacity={0.75}
      />
    </motion.g>
  );
}

function Wing({ variants }: { variants: Variants }) {
  return (
    <motion.g variants={variants} style={pivot(76, 144)}>
      <path
        d="M80 138 C58 140 42 160 42 186 C42 198 46 208 52 214 C54 206 58 206 60 212 C62 204 67 204 69 209 C76 192 82 170 82 148 Z"
        fill={C.wing}
        {...strokeProps}
      />
      <path
        d="M70 156 C62 168 58 182 58 196"
        fill="none"
        stroke={C.wingLight}
        strokeWidth={3}
        strokeLinecap="round"
      />
      <path
        d="M76 162 C72 174 69 186 68 198"
        fill="none"
        stroke={C.wingLight}
        strokeWidth={2.5}
        strokeLinecap="round"
        opacity={0.8}
      />
    </motion.g>
  );
}

interface EyeProps {
  cx: number;
  cy: number;
  side: "left" | "right";
  clipId: string;
  blink: boolean;
  v: OwlVariants;
}

function Eye({ cx, cy, side, clipId, blink, v }: EyeProps) {
  // Highlights sit on the same side for both eyes, as if lit from one window.
  const happyArc = `M${cx - 13} ${cy + 5} Q${cx} ${cy - 13} ${cx + 13} ${cy + 5}`;
  return (
    <g>
      <clipPath id={clipId}>
        <circle cx={cx} cy={cy} r={EYE_R} />
      </clipPath>

      <motion.g variants={v.openEye}>
        <circle cx={cx} cy={cy} r={EYE_R} fill={C.eyeWhite} />
        <g clipPath={`url(#${clipId})`}>
          <motion.g variants={v.pupil} style={pivot(cx, cy)}>
            <circle cx={cx + (side === "left" ? 2 : -2)} cy={cy + 2} r={15} fill={C.iris} />
            <circle cx={cx + (side === "left" ? 2 : -2)} cy={cy + 2} r={11} fill={C.pupil} />
            <circle
              cx={cx + (side === "left" ? 7 : 3)}
              cy={cy - 4}
              r={5.2}
              fill={C.eyeWhite}
            />
            <circle
              cx={cx + (side === "left" ? -3 : -7)}
              cy={cy + 7}
              r={2.3}
              fill={C.eyeWhite}
              opacity={0.9}
            />
          </motion.g>
          <motion.ellipse
            cx={cx}
            cy={cy}
            rx={EYE_R + 2}
            ry={EYE_R + 2}
            fill={C.lid}
            style={pivot(cx, cy - EYE_R - 2)}
            initial={false}
            animate={{ scaleY: blink ? 1 : 0 }}
            transition={{ duration: blink ? 0.07 : 0.11, ease: "easeOut" }}
          />
          <motion.path
            d={`M${cx - 20} ${cy + 3} Q${cx} ${cy + 13} ${cx + 20} ${cy + 3}`}
            fill="none"
            stroke={C.outline}
            strokeWidth={3.5}
            strokeLinecap="round"
            initial={false}
            animate={{ opacity: blink ? 1 : 0 }}
            transition={{ duration: 0.05, delay: blink ? 0.05 : 0 }}
          />
        </g>
        <circle cx={cx} cy={cy} r={EYE_R} fill="none" stroke={C.outline} strokeWidth={2.5} />
      </motion.g>

      <motion.path
        variants={v.happyEye}
        d={happyArc}
        fill="none"
        stroke={C.outline}
        strokeWidth={5}
        strokeLinecap="round"
      />
    </g>
  );
}

function Beak({ v }: { v: OwlVariants }) {
  return (
    <g>
      <motion.ellipse
        variants={v.mouth}
        style={pivot(120, 128)}
        cx={120}
        cy={139}
        rx={10.5}
        ry={12}
        fill={C.mouth}
      />
      <motion.g variants={v.mouth} style={pivot(120, 128)}>
        <ellipse cx={120} cy={147} rx={6} ry={3.6} fill={C.tongue} />
      </motion.g>
      <motion.path
        variants={v.lowerBeak}
        d="M112.5 130 C114 137 117 140 120 140 C123 140 126 137 127.5 130 Z"
        fill={C.beakShade}
        {...strokeProps}
        strokeWidth={2.5}
      />
      <path
        d="M106 116 C112 110 128 110 134 116 C131 125 125 132 120 138 C115 132 109 125 106 116 Z"
        fill={C.beak}
        {...strokeProps}
        strokeWidth={2.5}
      />
      <path
        d="M112 117 C116 115 121 115 124 116"
        fill="none"
        stroke="#FFFFFF"
        strokeWidth={2.2}
        strokeLinecap="round"
        opacity={0.55}
      />
    </g>
  );
}

function Sparkle({ x, y, r, variants }: { x: number; y: number; r: number; variants: Variants }) {
  const k = r * 0.28;
  const d = `M${x} ${y - r} Q${x + k} ${y - k} ${x + r} ${y} Q${x + k} ${y + k} ${x} ${y + r} Q${x - k} ${y + k} ${x - r} ${y} Q${x - k} ${y - k} ${x} ${y - r} Z`;
  return <motion.path variants={variants} style={pivot(x, y)} d={d} fill={C.sparkle} />;
}

/* -------------------------------------------------------------------------- */
/* Owl                                                                        */
/* -------------------------------------------------------------------------- */

export default function Owl({ state = "idle", size = 200, className }: OwlProps) {
  // Apply the reduced motion preference after mount so server and client
  // markup match during hydration.
  const prefersReduced = useReducedMotion() ?? false;
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const reduce = mounted && prefersReduced;
  const v = reduce ? REDUCED_VARIANTS : MOTION_VARIANTS;
  const blink = useBlink();

  const uid = useId().replace(/[^a-zA-Z0-9_-]/g, "");
  const ids = {
    bodyClip: `pip-body-${uid}`,
    headClip: `pip-head-${uid}`,
    eyeL: `pip-eye-l-${uid}`,
    eyeR: `pip-eye-r-${uid}`,
  };

  const headPath =
    "M120 38 C163 38 192 64 192 100 C192 138 160 158 120 158 C80 158 48 138 48 100 C48 64 77 38 120 38 Z";

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 240 240"
      className={className}
      role="img"
      aria-label="Pip the owl"
      style={{ overflow: "visible" }}
    >
      <defs>
        <clipPath id={ids.bodyClip}>
          <ellipse cx={120} cy={172} rx={58} ry={52} />
        </clipPath>
        <clipPath id={ids.headClip}>
          <path d={headPath} />
        </clipPath>
      </defs>

      {/* key remounts the tree so a reduced motion change restarts cleanly */}
      <motion.g key={reduce ? "still" : "motion"} initial={false} animate={state}>
        {/* Ground shadow */}
        <motion.ellipse
          variants={v.shadow}
          style={pivot(120, GROUND_Y + 2)}
          cx={120}
          cy={GROUND_Y + 2}
          rx={50}
          ry={6}
          fill={C.shadow}
        />

        <motion.g variants={v.body} style={pivot(120, GROUND_Y)}>
          {/* Body */}
          <ellipse cx={120} cy={172} rx={58} ry={52} fill={C.body} />
          <g clipPath={`url(#${ids.bodyClip})`}>
            <ellipse cx={136} cy={210} rx={70} ry={34} fill={C.bodyShade} opacity={0.55} />
          </g>
          <ellipse cx={120} cy={172} rx={58} ry={52} fill="none" {...strokeProps} />

          {/* Belly with soft feather marks */}
          <ellipse cx={120} cy={180} rx={37} ry={38} fill={C.belly} />
          <g
            fill="none"
            stroke={C.bellyMark}
            strokeWidth={2.6}
            strokeLinecap="round"
          >
            <path d="M101 170 q5 5 10 0 M115 170 q5 5 10 0 M129 170 q5 5 10 0" />
            <path d="M108 184 q5 5 10 0 M122 184 q5 5 10 0" />
            <path d="M115 198 q5 5 10 0" />
          </g>

          {/* Feet */}
          <g fill={C.feet} {...strokeProps} strokeWidth={2.5}>
            <ellipse cx={95} cy={222} rx={5.5} ry={6.5} />
            <ellipse cx={104} cy={224} rx={5.5} ry={6.5} />
            <ellipse cx={113} cy={222} rx={5.5} ry={6.5} />
            <ellipse cx={127} cy={222} rx={5.5} ry={6.5} />
            <ellipse cx={136} cy={224} rx={5.5} ry={6.5} />
            <ellipse cx={145} cy={222} rx={5.5} ry={6.5} />
          </g>

          {/* Wings */}
          <Wing variants={v.wing} />
          <g transform={MIRROR}>
            <Wing variants={v.wing} />
          </g>

          {/* Head */}
          <motion.g variants={v.head} style={pivot(NECK.x, NECK.y)}>
            <Tuft variants={v.tuft} />
            <g transform={MIRROR}>
              <Tuft variants={v.tuft} />
            </g>

            <path d={headPath} fill={C.body} />
            <g clipPath={`url(#${ids.headClip})`}>
              <ellipse cx={96} cy={52} rx={44} ry={18} fill="#FFFFFF" opacity={0.12} />
            </g>
            <path d={headPath} fill="none" {...strokeProps} />

            {/* Facial disc */}
            <g fill={C.face}>
              <circle cx={EYE_L.x} cy={EYE_L.y} r={35} />
              <circle cx={EYE_R_POS.x} cy={EYE_R_POS.y} r={35} />
              <ellipse cx={120} cy={122} rx={30} ry={22} />
            </g>

            {/* Cheeks */}
            <motion.g variants={v.cheek} fill={C.cheek}>
              <ellipse cx={70} cy={128} rx={10} ry={6} />
              <ellipse cx={170} cy={128} rx={10} ry={6} />
            </motion.g>

            {/* Eyes */}
            <Eye cx={EYE_L.x} cy={EYE_L.y} side="left" clipId={ids.eyeL} blink={blink} v={v} />
            <Eye cx={EYE_R_POS.x} cy={EYE_R_POS.y} side="right" clipId={ids.eyeR} blink={blink} v={v} />

            {/* Brows */}
            <g fill="none" stroke={C.brow} strokeWidth={5} strokeLinecap="round">
              <motion.path variants={v.browLeft} style={pivot(92, 66)} d="M79 69 Q92 61 105 66" />
              <motion.path variants={v.browRight} style={pivot(148, 66)} d="M161 69 Q148 61 135 66" />
            </g>

            <Beak v={v} />
          </motion.g>
        </motion.g>

        {/* Question mark for the confused state */}
        <motion.g variants={v.question} style={pivot(206, 44)}>
          <path
            d="M197 34 C197 22 215 21 215 33 C215 42 206 42 206 51"
            fill="none"
            stroke={C.accent}
            strokeWidth={6.5}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <circle cx={206} cy={62} r={4.2} fill={C.accent} />
        </motion.g>

        {/* Thought dots for the thinking state */}
        {[
          { x: 196, y: 50, r: 4 },
          { x: 208, y: 36, r: 5.5 },
          { x: 222, y: 20, r: 7 },
        ].map((dot, i) => (
          <motion.circle
            key={i}
            variants={v.dots[i]}
            style={pivot(dot.x, dot.y)}
            cx={dot.x}
            cy={dot.y}
            r={dot.r}
            fill={C.wing}
          />
        ))}

        {/* Sparkles for the celebrating state */}
        <Sparkle x={34} y={64} r={10} variants={v.sparkles[0]} />
        <Sparkle x={210} y={58} r={12} variants={v.sparkles[1]} />
        <Sparkle x={26} y={150} r={7} variants={v.sparkles[2]} />
        <Sparkle x={216} y={146} r={8} variants={v.sparkles[3]} />
      </motion.g>
    </svg>
  );
}
