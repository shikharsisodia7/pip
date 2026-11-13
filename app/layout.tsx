import type { Metadata } from 'next';
import { Andika, Fredoka, Nunito } from 'next/font/google';
import DebugPanel from '@/components/debug/DebugPanel';
import './globals.css';

const fredoka = Fredoka({ subsets: ['latin'], variable: '--font-fredoka' });
const nunito = Nunito({ subsets: ['latin'], variable: '--font-nunito' });
const andika = Andika({ subsets: ['latin'], weight: ['400', '700'], variable: '--font-andika' });

export const metadata: Metadata = {
  title: 'Pip Reads It Wrong',
  description: 'A reading buddy owl who learns to read from your child.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${fredoka.variable} ${nunito.variable} ${andika.variable} h-full antialiased`}>
      <body className="min-h-full bg-cream font-sans text-ink">
        {children}
        <DebugPanel />
      </body>
    </html>
  );
}
