import type { HomeLayoutProps } from "fumadocs-ui/layouts/home";

/**
 * Shared layout configurations
 *
 * you can configure layouts individually from:
 * Home Layout: app/(home)/layout.tsx
 * Docs Layout: app/docs/layout.tsx
 */
export const baseOptions: HomeLayoutProps = {
  nav: {
    title: "MINIMA Meet",
  },
  githubUrl: "https://github.com/minima-solutions/cal.com",
  links: [
    {
      text: "Design",
      url: "/design",
      active: "nested-url",
    },
    {
      text: "GitHub",
      url: "https://github.com/minima-solutions/cal.com",
    },
  ],
};
