import type {Metadata} from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Arena Project Home — Metacade",
  description:
    "Public reference implementation of an Arena Project Home on Robinhood Chain, with a Chainlink-backed oracle guard. Reference build; the wider Arena is not live on this chain."
};

export default function RootLayout({children}: {children: React.ReactNode}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
