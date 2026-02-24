"use client";

import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "motion/react";

interface RollingDigitProps {
  digit: string;
  delay?: number;
}

function RollingDigit({ digit, delay = 0 }: RollingDigitProps) {
  const [current, setCurrent] = useState(digit);
  const [prev, setPrev] = useState<string | null>(null);
  const isFirstRender = useRef(true);

  useEffect(() => {
    if (isFirstRender.current) {
      isFirstRender.current = false;
      setCurrent(digit);
      return;
    }
    if (digit !== current) {
      setPrev(current);
      setCurrent(digit);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [digit]);

  return (
    <span className="relative inline-flex overflow-hidden" style={{ width: digit === "," || digit === "." ? "0.35em" : "0.65em" }}>
      <AnimatePresence mode="popLayout">
        {prev && (
          <motion.span
            key={`out-${prev}-${Date.now()}`}
            initial={{ y: 0, opacity: 1 }}
            animate={{ y: "-110%", opacity: 0 }}
            exit={{ y: "-110%", opacity: 0 }}
            transition={{ duration: 0.4, delay, ease: [0.4, 0, 0.2, 1] }}
            className="absolute inset-0 flex items-center justify-center"
            onAnimationComplete={() => setPrev(null)}
          >
            {prev}
          </motion.span>
        )}
        <motion.span
          key={`in-${current}`}
          initial={prev ? { y: "110%", opacity: 0 } : false}
          animate={{ y: 0, opacity: 1 }}
          transition={{ duration: 0.4, delay, ease: [0.4, 0, 0.2, 1] }}
          className="flex items-center justify-center"
        >
          {current}
        </motion.span>
      </AnimatePresence>
    </span>
  );
}

interface RollingNumberProps {
  value: number;
  format?: (v: number) => string;
  className?: string;
}

export default function RollingNumber({ value, format, className = "" }: RollingNumberProps) {
  const display = format ? format(value) : value.toString();
  const chars = display.split("");

  return (
    <span className={`inline-flex items-center tabular-nums ${className}`}>
      {chars.map((ch, i) => {
        const isDigit = /\d/.test(ch);
        if (!isDigit) {
          return <span key={`sep-${i}-${ch}`} style={{ width: ch === " " ? "0.25em" : undefined }}>{ch}</span>;
        }
        return <RollingDigit key={`d-${i}`} digit={ch} delay={i * 0.03} />;
      })}
    </span>
  );
}

interface RollingScoreProps {
  home: number | null;
  away: number | null;
  inProgress?: boolean;
  className?: string;
  separatorClass?: string;
}

export function RollingScore({ home, away, inProgress, className = "", separatorClass = "" }: RollingScoreProps) {
  const h = inProgress ? (home ?? 0) : (home ?? 0);
  const a = inProgress ? (away ?? 0) : (away ?? 0);

  return (
    <span className={`inline-flex items-center gap-2 ${className}`}>
      <RollingNumber value={h} className="text-[#F3F4F6] font-black" />
      <span className={`font-medium ${separatorClass || "text-[#9CA3AF]"}`}>—</span>
      <RollingNumber value={a} className="text-[#F3F4F6] font-black" />
    </span>
  );
}
