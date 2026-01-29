/**
 * Unit tests for CompletionProvider
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { CompletionProvider } from '../../completion';
import { MetadataLoader } from '../../metadata';
import { CompletionItemKind } from 'vscode-languageserver/node';
import * as path from 'path';

describe('CompletionProvider', () => {
  const testMetadataPath = path.join(__dirname, '../fixtures/test-metadata.json');
  let loader: MetadataLoader;
  let provider: CompletionProvider;

  beforeEach(() => {
    loader = new MetadataLoader(testMetadataPath);
    loader.load();
    provider = new CompletionProvider(loader);
  });

  describe('getCompletions', () => {
    it('returns completion items for all functions', () => {
      const completions = provider.getCompletions();

      expect(completions).toHaveLength(5);
      expect(completions[0]).toHaveProperty('label');
      expect(completions[0]).toHaveProperty('kind');
      expect(completions[0]).toHaveProperty('detail');
      expect(completions[0]).toHaveProperty('documentation');
    });

    it('sets kind to Function', () => {
      const completions = provider.getCompletions();

      for (const item of completions) {
        expect(item.kind).toBe(CompletionItemKind.Function);
      }
    });

    it('includes function signature as detail', () => {
      const completions = provider.getCompletions();
      const jsonObject = completions.find(c => c.label === 'json_object');

      expect(jsonObject?.detail).toContain('JSON');
    });

    it('includes documentation in Markdown format', () => {
      const completions = provider.getCompletions();
      const jsonObject = completions.find(c => c.label === 'json_object');

      expect(jsonObject?.documentation).toBeDefined();
      expect(jsonObject?.documentation).toHaveProperty('kind', 'markdown');
      expect(jsonObject?.documentation).toHaveProperty('value');
    });

    it('formats documentation with function name in bold', () => {
      const completions = provider.getCompletions();
      const jsonObject = completions.find(c => c.label === 'json_object');

      const docValue = typeof jsonObject?.documentation === 'object'
        ? jsonObject.documentation.value
        : '';

      expect(docValue).toContain('**json_object**');
    });

    it('includes library information in documentation', () => {
      const completions = provider.getCompletions();
      const jsonObject = completions.find(c => c.label === 'json_object');

      const docValue = typeof jsonObject?.documentation === 'object'
        ? jsonObject.documentation.value
        : '';

      expect(docValue).toContain('Library:');
    });

    it('returns empty array when no metadata loaded', () => {
      const emptyLoader = new MetadataLoader(testMetadataPath);
      const emptyProvider = new CompletionProvider(emptyLoader);
      const completions = emptyProvider.getCompletions();

      expect(completions).toHaveLength(0);
    });
  });

  describe('getCompletionsByPrefix', () => {
    it('filters completions by prefix', () => {
      const completions = provider.getCompletionsByPrefix('json_');

      expect(completions.length).toBe(1);
      expect(completions[0].label).toBe('json_object');
    });

    it('returns all completions for empty prefix', () => {
      const completions = provider.getCompletionsByPrefix('');

      expect(completions).toHaveLength(5);
    });

    it('is case-insensitive', () => {
      const completions = provider.getCompletionsByPrefix('JSON_');

      expect(completions.length).toBe(1);
      expect(completions[0].label).toBe('json_object');
    });

    it('returns empty array for no matches', () => {
      const completions = provider.getCompletionsByPrefix('xyz_');

      expect(completions).toHaveLength(0);
    });

    it('handles array_ prefix correctly', () => {
      const completions = provider.getCompletionsByPrefix('array_');

      expect(completions.length).toBe(1);
      expect(completions[0].label).toBe('array_sort');
    });

    it('handles http_ prefix correctly', () => {
      const completions = provider.getCompletionsByPrefix('http_');

      expect(completions.length).toBe(1);
      expect(completions[0].label).toBe('http_get');
    });

    it('handles validate_ prefix correctly', () => {
      const completions = provider.getCompletionsByPrefix('validate_');

      expect(completions.length).toBe(1);
      expect(completions[0].label).toBe('validate_email');
    });
  });

  describe('edge cases', () => {
    it('handles functions with minimal metadata', () => {
      const completions = provider.getCompletions();

      // All completions should have at least label and kind
      for (const item of completions) {
        expect(item.label).toBeTruthy();
        expect(item.kind).toBeDefined();
      }
    });

    it('handles special characters in prefix', () => {
      const completions = provider.getCompletionsByPrefix('_');

      // Should not crash
      expect(Array.isArray(completions)).toBe(true);
    });

    it('handles very long prefix', () => {
      const longPrefix = 'a'.repeat(100);
      const completions = provider.getCompletionsByPrefix(longPrefix);

      expect(completions).toHaveLength(0);
    });

    it('preserves original function order', () => {
      const completions = provider.getCompletions();
      const labels = completions.map(c => c.label);

      // Order should be consistent across calls
      const completions2 = provider.getCompletions();
      const labels2 = completions2.map(c => c.label);

      expect(labels).toEqual(labels2);
    });
  });

  describe('performance', () => {
    it('completes quickly for large result sets', () => {
      const startTime = Date.now();
      provider.getCompletions();
      const endTime = Date.now();

      // Should complete in less than 100ms
      expect(endTime - startTime).toBeLessThan(100);
    });

    it('prefix filtering is fast', () => {
      const startTime = Date.now();
      provider.getCompletionsByPrefix('json');
      const endTime = Date.now();

      // Should complete in less than 50ms
      expect(endTime - startTime).toBeLessThan(50);
    });
  });
});
