/**
 * Metadata loading and management for MAINFRAME functions
 */

import * as fs from 'fs';
import * as path from 'path';

export interface FunctionMeta {
  name: string;
  description: string;
  signature: string;
  library: string;
  category: string;
}

export interface MetadataStats {
  totalFunctions: number;
  libraries: Set<string>;
  categories: Set<string>;
}

export class MetadataLoader {
  private functionMap: Map<string, FunctionMeta> = new Map();
  private metadataPath: string;

  constructor(metadataPath?: string) {
    if (metadataPath) {
      this.metadataPath = metadataPath;
    } else {
      const mainframeRoot = process.env.MAINFRAME_ROOT || path.join(process.env.HOME || '', '.mainframe');
      this.metadataPath = path.join(mainframeRoot, 'FUNCTIONS.lsp.json');
    }
  }

  /**
   * Load metadata from FUNCTIONS.lsp.json
   */
  load(): { success: boolean; error?: string; stats?: MetadataStats } {
    try {
      if (!fs.existsSync(this.metadataPath)) {
        return {
          success: false,
          error: `Metadata file not found: ${this.metadataPath}`,
        };
      }

      const content = fs.readFileSync(this.metadataPath, 'utf-8');
      const data = JSON.parse(content);

      if (!data.completions || !Array.isArray(data.completions)) {
        return {
          success: false,
          error: 'Invalid metadata format: missing completions array',
        };
      }

      // Clear existing data
      this.functionMap.clear();

      // Build function lookup map
      for (const completion of data.completions) {
        if (!completion.label) continue;

        const library = completion.detail?.split(' - ')[0] || 'unknown';
        const category = completion.tags?.[0] || 'other';

        this.functionMap.set(completion.label, {
          name: completion.label,
          description: completion.documentation || '',
          signature: completion.detail || completion.label,
          library,
          category,
        });
      }

      const stats: MetadataStats = {
        totalFunctions: this.functionMap.size,
        libraries: new Set(Array.from(this.functionMap.values()).map(f => f.library)),
        categories: new Set(Array.from(this.functionMap.values()).map(f => f.category)),
      };

      return { success: true, stats };
    } catch (error) {
      return {
        success: false,
        error: `Failed to parse metadata: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }

  /**
   * Get function metadata by name
   */
  getFunction(name: string): FunctionMeta | undefined {
    return this.functionMap.get(name);
  }

  /**
   * Get all functions
   */
  getAllFunctions(): FunctionMeta[] {
    return Array.from(this.functionMap.values());
  }

  /**
   * Search functions by prefix
   */
  searchByPrefix(prefix: string): FunctionMeta[] {
    const results: FunctionMeta[] = [];
    const lowerPrefix = prefix.toLowerCase();

    for (const meta of this.functionMap.values()) {
      if (meta.name.toLowerCase().startsWith(lowerPrefix)) {
        results.push(meta);
      }
    }

    return results;
  }

  /**
   * Search functions by category
   */
  searchByCategory(category: string): FunctionMeta[] {
    return Array.from(this.functionMap.values()).filter(
      meta => meta.category === category
    );
  }

  /**
   * Get statistics about loaded metadata
   */
  getStats(): MetadataStats {
    return {
      totalFunctions: this.functionMap.size,
      libraries: new Set(Array.from(this.functionMap.values()).map(f => f.library)),
      categories: new Set(Array.from(this.functionMap.values()).map(f => f.category)),
    };
  }

  /**
   * Check if metadata is loaded
   */
  isLoaded(): boolean {
    return this.functionMap.size > 0;
  }

  /**
   * Get the metadata file path
   */
  getMetadataPath(): string {
    return this.metadataPath;
  }
}
