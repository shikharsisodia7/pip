'use client';

// Live pitch contour: the reader's voice drawn as a smooth glowing line that
// rises and falls with their pitch, over a dull flat line showing how Pip read
// it. Built to be readable from the back of a room.

import { useMemo } from 'react';
import { motion } from 'framer-motion';
import type { ProsodyFrame } from '@/lib/types';

const W = 1000;
const H = 320;
const PAD_X = 28;
const RANGE_ST = 9; // semitones above and below the speaker's median shown on screen

export interface PitchContourProps {
  frames: ProsodyFrame[];
  /** Seconds shown across the panel. The line compresses if speech runs longer. */
  windowSec?: number;
  active?: boolean;
  /** Shows the "Pip" label on the flat line. */
  showPipLine?: boolean;
  className?: string;
}

interface Pt { x: number; y: number }

function yFor(st: number) {
  const clamped = Math.max(-RANGE_ST, Math.min(RANGE_ST, st));
  return H / 2 - (clamped / RANGE_ST) * (H / 2 - 30);
}

/** Catmull-Rom spline through points, as an SVG path. */
function smoothPath(pts: Pt[]): string {
  if (pts.length === 0) return '';
  if (pts.length === 1) return `M${pts[0].x},${pts[0].y} l0.1,0`;
  let d = `M${pts[0].x.toFixed(1)},${pts[0].y.toFixed(1)}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] ?? pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] ?? p2;
    const c1x = p1.x + (p2.x - p0.x) / 6;
    const c1y = p1.y + (p2.y - p0.y) / 6;
    const c2x = p2.x - (p3.x - p1.x) / 6;
    const c2y = p2.y - (p3.y - p1.y) / 6;
    d += ` C${c1x.toFixed(1)},${c1y.toFixed(1)} ${c2x.toFixed(1)},${c2y.toFixed(1)} ${p2.x.toFixed(1)},${p2.y.toFixed(1)}`;
  }
  return d;
}

export default function PitchContour({ frames, windowSec = 5, active = false, showPipLine = true, className }: PitchContourProps) {
  const { segments, head } = useMemo(() => {
    const voiced = frames.filter((f) => f.semitones !== null);
    const span = Math.max(windowSec, frames.length ? frames[frames.length - 1].t - frames[0].t : 0);
    const t0 = frames.length ? frames[0].t : 0;
    const xFor = (t: number) => PAD_X + ((t - t0) / span) * (W - PAD_X * 2);

    // Split into segments at gaps longer than 250 ms so pauses read as pauses.
    const segs: Pt[][] = [];
    let cur: Pt[] = [];
    let lastT = -Infinity;
    for (const f of voiced) {
      if (f.t - lastT > 0.25 && cur.length) {
        segs.push(cur);
        cur = [];
      }
      cur.push({ x: xFor(f.t), y: yFor(f.semitones as number) });
      lastT = f.t;
    }
    if (cur.length) segs.push(cur);
    const last = voiced[voiced.length - 1];
    return {
      segments: segs.map(smoothPath),
      head: last ? { x: xFor(last.t), y: yFor(last.semitones as number) } : null,
    };
  }, [frames, windowSec]);

  return (
    <div className={className}>
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label="Your voice, drawn as a line that goes up and down">
        <defs>
          <linearGradient id="pc-bg" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#fffdf8" />
            <stop offset="100%" stopColor="#fff2c9" />
          </linearGradient>
          <linearGradient id="pc-line" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#ffb547" />
            <stop offset="55%" stopColor="#ff7a59" />
            <stop offset="100%" stopColor="#3a5bdc" />
          </linearGradient>
          <filter id="pc-glow" x="-10%" y="-30%" width="120%" height="160%">
            <feGaussianBlur stdDeviation="7" result="b" />
            <feMerge>
              <feMergeNode in="b" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        <rect x="0" y="0" width={W} height={H} rx="28" fill="url(#pc-bg)" />
        {[-6, -3, 3, 6].map((st) => (
          <line key={st} x1={PAD_X} x2={W - PAD_X} y1={yFor(st)} y2={yFor(st)} stroke="#efe3cf" strokeWidth="2" strokeDasharray="4 10" />
        ))}

        {showPipLine && (
          <g>
            <line x1={PAD_X} x2={W - PAD_X} y1={H / 2} y2={H / 2} stroke="#b9ab99" strokeWidth="7" strokeLinecap="round" opacity="0.55" />
            <text x={W - PAD_X - 4} y={H / 2 - 14} textAnchor="end" fontSize="22" fill="#8f7f6c" fontFamily="var(--font-nunito), system-ui">
              how Pip said it
            </text>
          </g>
        )}

        <g filter="url(#pc-glow)">
          {segments.map((d, i) => (
            <path key={i} d={d} fill="none" stroke="url(#pc-line)" strokeWidth="12" strokeLinecap="round" strokeLinejoin="round" />
          ))}
        </g>

        {head && active && (
          <motion.circle
            cx={head.x}
            cy={head.y}
            r={13}
            fill="#ff7a59"
            stroke="#fff"
            strokeWidth={4}
            animate={{ r: [12, 16, 12] }}
            transition={{ duration: 0.9, repeat: Infinity }}
          />
        )}

        {!segments.length && (
          <text x={W / 2} y={H / 2 + 70} textAnchor="middle" fontSize="26" fill="#8f7f6c" fontFamily="var(--font-nunito), system-ui">
            {active ? 'Say it out loud!' : 'Your voice will draw here'}
          </text>
        )}
      </svg>
    </div>
  );
}
