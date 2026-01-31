#!/usr/bin/env bash
# =============================================================================
# Setup demo project for MAINFRAME agent-intelligence demo
# =============================================================================

set -euo pipefail

DEMO_DIR="${1:-/tmp/mystery-saas}"

rm -rf "$DEMO_DIR"
mkdir -p "$DEMO_DIR"
cd "$DEMO_DIR"

# Create package.json
cat > package.json << 'EOF'
{
  "name": "mystery-saas",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "next": "14.0.0",
    "react": "18.2.0",
    "react-dom": "18.2.0",
    "prisma": "5.0.0",
    "@prisma/client": "5.0.0",
    "tailwindcss": "3.3.0",
    "zod": "3.22.0"
  },
  "devDependencies": {
    "typescript": "5.0.0",
    "@types/react": "18.2.0",
    "eslint": "8.0.0",
    "vitest": "1.0.0"
  },
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "test": "vitest",
    "lint": "eslint ."
  }
}
EOF

# Create tsconfig.json
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "strict": true,
    "jsx": "preserve"
  }
}
EOF

# Create next.config.mjs
cat > next.config.mjs << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
}
export default nextConfig
EOF

# Create vitest.config.ts
cat > vitest.config.ts << 'EOF'
import { defineConfig } from 'vitest/config'
export default defineConfig({
  test: { globals: true }
})
EOF

# Create directory structure
mkdir -p src/app src/components src/lib src/hooks

# Create realistic source files with varying sizes

# Large file: db.ts (database layer)
cat > src/lib/db.ts << 'TYPESCRIPT'
import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient }

export const prisma = globalForPrisma.prisma || new PrismaClient({
  log: ['query', 'info', 'warn', 'error'],
})

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma

export async function getUsers(limit = 10) {
  return prisma.user.findMany({ take: limit, orderBy: { createdAt: 'desc' } })
}

export async function getUserById(id: string) {
  return prisma.user.findUnique({ where: { id } })
}

export async function createUser(data: { email: string; name: string }) {
  return prisma.user.create({ data })
}

export async function updateUser(id: string, data: Partial<{ email: string; name: string }>) {
  return prisma.user.update({ where: { id }, data })
}

export async function deleteUser(id: string) {
  return prisma.user.delete({ where: { id } })
}

export async function getProjects(userId: string) {
  return prisma.project.findMany({
    where: { userId },
    include: { tasks: true },
    orderBy: { updatedAt: 'desc' }
  })
}

export async function createProject(data: { name: string; userId: string; description?: string }) {
  return prisma.project.create({ data })
}

export async function getProjectWithTasks(projectId: string) {
  return prisma.project.findUnique({
    where: { id: projectId },
    include: { tasks: { orderBy: { createdAt: 'desc' } }, user: true }
  })
}

export async function createTask(data: {
  title: string
  projectId: string
  status?: 'pending' | 'in_progress' | 'completed'
}) {
  return prisma.task.create({ data: { ...data, status: data.status || 'pending' } })
}

export async function updateTaskStatus(taskId: string, status: 'pending' | 'in_progress' | 'completed') {
  return prisma.task.update({ where: { id: taskId }, data: { status } })
}
TYPESCRIPT

# Medium file: auth.ts (authentication)
cat > src/lib/auth.ts << 'TYPESCRIPT'
import { z } from 'zod'

const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  name: z.string().min(1),
  role: z.enum(['admin', 'user', 'guest']),
})

type User = z.infer<typeof UserSchema>

export async function validateSession(token: string): Promise<User | null> {
  if (!token || token.length < 10) return null
  // In production: verify JWT, check database
  return { id: 'user-1', email: 'demo@example.com', name: 'Demo User', role: 'user' }
}

export async function createSession(user: User): Promise<string> {
  // In production: create JWT with expiration
  return `session-${user.id}-${Date.now()}`
}

export function requireAuth(handler: Function) {
  return async (req: Request) => {
    const token = req.headers.get('authorization')?.replace('Bearer ', '')
    const user = token ? await validateSession(token) : null
    if (!user) return new Response('Unauthorized', { status: 401 })
    return handler(req, user)
  }
}
TYPESCRIPT

# Small file: page.tsx (main page)
cat > src/app/page.tsx << 'TYPESCRIPT'
import { Header } from '@/components/Header'
import { ProjectList } from '@/components/ProjectList'

export default function Home() {
  return (
    <main className="min-h-screen p-8">
      <Header />
      <ProjectList />
    </main>
  )
}
TYPESCRIPT

# Small file: layout.tsx
cat > src/app/layout.tsx << 'TYPESCRIPT'
import './globals.css'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Mystery SaaS',
  description: 'A project management tool',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
TYPESCRIPT

# Component files
cat > src/components/Header.tsx << 'TYPESCRIPT'
'use client'

import { useState } from 'react'

export function Header() {
  const [isMenuOpen, setIsMenuOpen] = useState(false)

  return (
    <header className="flex items-center justify-between p-4 border-b">
      <h1 className="text-2xl font-bold">Mystery SaaS</h1>
      <nav className={isMenuOpen ? 'block' : 'hidden md:block'}>
        <a href="/projects">Projects</a>
        <a href="/settings">Settings</a>
      </nav>
      <button onClick={() => setIsMenuOpen(!isMenuOpen)}>Menu</button>
    </header>
  )
}
TYPESCRIPT

cat > src/components/ProjectList.tsx << 'TYPESCRIPT'
'use client'

import { useProjects } from '@/hooks/useProjects'

export function ProjectList() {
  const { projects, isLoading, error } = useProjects()

  if (isLoading) return <div>Loading projects...</div>
  if (error) return <div>Error: {error.message}</div>

  return (
    <ul className="space-y-4">
      {projects.map((project) => (
        <li key={project.id} className="p-4 border rounded">
          <h3 className="font-semibold">{project.name}</h3>
          <p className="text-gray-600">{project.description}</p>
          <span className="text-sm">{project.tasks.length} tasks</span>
        </li>
      ))}
    </ul>
  )
}
TYPESCRIPT

# Hooks file
cat > src/hooks/useProjects.ts << 'TYPESCRIPT'
import { useState, useEffect } from 'react'

interface Project {
  id: string
  name: string
  description: string
  tasks: { id: string; title: string; status: string }[]
}

export function useProjects() {
  const [projects, setProjects] = useState<Project[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  useEffect(() => {
    fetch('/api/projects')
      .then((res) => res.json())
      .then(setProjects)
      .catch(setError)
      .finally(() => setIsLoading(false))
  }, [])

  return { projects, isLoading, error }
}
TYPESCRIPT

echo "Demo project created at: $DEMO_DIR"
echo "Files:"
find "$DEMO_DIR" -type f -name "*.ts*" -o -name "*.json" | head -20
