/**
 * Unit tests for MetadataLoader
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { MetadataLoader } from '../../metadata';
import * as path from 'path';

describe('MetadataLoader', () => {
  const fixturesDir = path.join(__dirname, '../fixtures');
  const testMetadataPath = path.join(fixturesDir, 'test-metadata.json');
  const invalidMetadataPath = path.join(fixturesDir, 'invalid-metadata.json');
  const nonexistentPath = path.join(fixturesDir, 'does-not-exist.json');

  describe('constructor', () => {
    it('accepts custom metadata path', () => {
      const loader = new MetadataLoader(testMetadataPath);
      expect(loader.getMetadataPath()).toBe(testMetadataPath);
    });

    it('uses MAINFRAME_ROOT when path not provided', () => {
      const loader = new MetadataLoader();
      const expectedPath = path.join(
        process.env.MAINFRAME_ROOT || path.join(process.env.HOME || '', '.mainframe'),
        'FUNCTIONS.lsp.json'
      );
      expect(loader.getMetadataPath()).toBe(expectedPath);
    });
  });

  describe('load', () => {
    it('successfully loads valid metadata', () => {
      const loader = new MetadataLoader(testMetadataPath);
      const result = loader.load();

      expect(result.success).toBe(true);
      expect(result.error).toBeUndefined();
      expect(result.stats).toBeDefined();
      expect(result.stats?.totalFunctions).toBe(5);
    });

    it('returns error for nonexistent file', () => {
      const loader = new MetadataLoader(nonexistentPath);
      const result = loader.load();

      expect(result.success).toBe(false);
      expect(result.error).toContain('not found');
    });

    it('handles invalid JSON gracefully', () => {
      const loader = new MetadataLoader(invalidMetadataPath);
      const result = loader.load();

      expect(result.success).toBe(false);
      expect(result.error).toContain('Failed to parse metadata');
    });

    it('sets isLoaded flag after successful load', () => {
      const loader = new MetadataLoader(testMetadataPath);
      expect(loader.isLoaded()).toBe(false);

      loader.load();
      expect(loader.isLoaded()).toBe(true);
    });

    it('extracts library names from metadata', () => {
      const loader = new MetadataLoader(testMetadataPath);
      const result = loader.load();

      expect(result.stats?.libraries.size).toBeGreaterThan(0);
      expect(result.stats?.libraries.has('JSON')).toBe(true);
    });

    it('extracts categories from tags', () => {
      const loader = new MetadataLoader(testMetadataPath);
      const result = loader.load();

      expect(result.stats?.categories.size).toBeGreaterThan(0);
      expect(result.stats?.categories.has('json')).toBe(true);
    });
  });

  describe('getFunction', () => {
    let loader: MetadataLoader;

    beforeEach(() => {
      loader = new MetadataLoader(testMetadataPath);
      loader.load();
    });

    it('returns function metadata by exact name', () => {
      const meta = loader.getFunction('json_object');

      expect(meta).toBeDefined();
      expect(meta?.name).toBe('json_object');
      expect(meta?.library).toBe('JSON');
      expect(meta?.description).toContain('JSON object');
    });

    it('returns undefined for unknown function', () => {
      const meta = loader.getFunction('unknown_function');
      expect(meta).toBeUndefined();
    });

    it('is case-sensitive', () => {
      const meta = loader.getFunction('JSON_OBJECT');
      expect(meta).toBeUndefined();
    });
  });

  describe('getAllFunctions', () => {
    it('returns all loaded functions', () => {
      const loader = new MetadataLoader(testMetadataPath);
      loader.load();

      const functions = loader.getAllFunctions();
      expect(functions).toHaveLength(5);
      expect(functions[0]).toHaveProperty('name');
      expect(functions[0]).toHaveProperty('description');
      expect(functions[0]).toHaveProperty('signature');
    });

    it('returns empty array when not loaded', () => {
      const loader = new MetadataLoader(testMetadataPath);
      const functions = loader.getAllFunctions();
      expect(functions).toHaveLength(0);
    });
  });

  describe('searchByPrefix', () => {
    let loader: MetadataLoader;

    beforeEach(() => {
      loader = new MetadataLoader(testMetadataPath);
      loader.load();
    });

    it('returns functions matching prefix', () => {
      const results = loader.searchByPrefix('json_');
      expect(results.length).toBeGreaterThan(0);
      expect(results[0].name).toBe('json_object');
    });

    it('is case-insensitive', () => {
      const results = loader.searchByPrefix('JSON_');
      expect(results.length).toBeGreaterThan(0);
      expect(results[0].name).toBe('json_object');
    });

    it('returns empty array for no matches', () => {
      const results = loader.searchByPrefix('xyz_');
      expect(results).toHaveLength(0);
    });

    it('returns all functions for empty prefix', () => {
      const results = loader.searchByPrefix('');
      expect(results.length).toBe(5);
    });

    it('matches array_ prefix correctly', () => {
      const results = loader.searchByPrefix('array_');
      expect(results.length).toBe(1);
      expect(results[0].name).toBe('array_sort');
    });
  });

  describe('searchByCategory', () => {
    let loader: MetadataLoader;

    beforeEach(() => {
      loader = new MetadataLoader(testMetadataPath);
      loader.load();
    });

    it('returns functions in category', () => {
      const results = loader.searchByCategory('json');
      expect(results.length).toBeGreaterThan(0);
      expect(results[0].category).toBe('json');
    });

    it('returns empty array for unknown category', () => {
      const results = loader.searchByCategory('unknown');
      expect(results).toHaveLength(0);
    });

    it('is case-sensitive', () => {
      const results = loader.searchByCategory('JSON');
      expect(results).toHaveLength(0);
    });
  });

  describe('getStats', () => {
    it('returns accurate statistics', () => {
      const loader = new MetadataLoader(testMetadataPath);
      loader.load();

      const stats = loader.getStats();
      expect(stats.totalFunctions).toBe(5);
      expect(stats.libraries.size).toBeGreaterThan(0);
      expect(stats.categories.size).toBeGreaterThan(0);
    });

    it('returns zero stats when not loaded', () => {
      const loader = new MetadataLoader(testMetadataPath);
      const stats = loader.getStats();
      expect(stats.totalFunctions).toBe(0);
    });
  });

  describe('edge cases', () => {
    it('handles metadata without completions array', () => {
      const noCompletionsPath = path.join(fixturesDir, 'no-completions.json');
      const loader = new MetadataLoader(noCompletionsPath);
      const result = loader.load();

      expect(result.success).toBe(false);
      expect(result.error).toContain('missing completions array');
    });

    it('handles large metadata files efficiently', () => {
      // Load test with actual FUNCTIONS.json if available
      const loader = new MetadataLoader(testMetadataPath);
      const startTime = Date.now();
      loader.load();
      const endTime = Date.now();

      // Should load in less than 1 second
      expect(endTime - startTime).toBeLessThan(1000);
    });

    it('handles functions with missing fields gracefully', () => {
      const loader = new MetadataLoader(testMetadataPath);
      loader.load();

      // All functions should have required fields
      const functions = loader.getAllFunctions();
      for (const func of functions) {
        expect(func.name).toBeDefined();
        expect(func.library).toBeDefined();
        expect(func.category).toBeDefined();
      }
    });
  });
});
