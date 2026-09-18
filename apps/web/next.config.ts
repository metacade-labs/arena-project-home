import type {NextConfig} from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // The page must never serve a cached chain read. Every request reads the chain.
  headers: async () => [
    {
      source: "/:path*",
      headers: [
        {key: "X-Content-Type-Options", value: "nosniff"},
        {key: "Referrer-Policy", value: "strict-origin-when-cross-origin"},
        {key: "X-Frame-Options", value: "DENY"}
      ]
    }
  ]
};

export default nextConfig;
