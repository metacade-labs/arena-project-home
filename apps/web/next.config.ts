import type {NextConfig} from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Caching is prevented at the route level by `dynamic = "force-dynamic"`, not here.
  // These headers are hardening only.
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
