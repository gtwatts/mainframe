/**
 * MAINFRAME Bash Language Support - VS Code Extension Client
 *
 * Provides IntelliSense for MAINFRAME's 2,000+ bash functions through
 * Language Server Protocol integration.
 */

import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import {
  workspace,
  window,
  commands,
  ExtensionContext,
  StatusBarAlignment,
  StatusBarItem,
  TextDocument,
  ThemeColor,
  Uri,
} from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;
let statusBar: StatusBarItem | undefined;

/**
 * Detect MAINFRAME installation path
 */
function detectMainframePath(): string | null {
  // Check environment variable
  const envPath = process.env.MAINFRAME_ROOT;
  if (envPath && fs.existsSync(path.join(envPath, 'lib', 'common.sh'))) {
    return envPath;
  }

  // Check default location
  const defaultPath = path.join(os.homedir(), '.mainframe');
  if (fs.existsSync(path.join(defaultPath, 'lib', 'common.sh'))) {
    return defaultPath;
  }

  return null;
}

/**
 * Get FUNCTIONS.json path from configuration or auto-detect
 */
function getFunctionsJsonPath(): string | null {
  // Check user configuration
  const configPath = workspace.getConfiguration('mainframe').get<string>('functionsPath');
  if (configPath && fs.existsSync(configPath)) {
    return configPath;
  }

  // Auto-detect from MAINFRAME installation
  const mainframePath = detectMainframePath();
  if (mainframePath) {
    const functionsPath = path.join(mainframePath, 'FUNCTIONS.json');
    if (fs.existsSync(functionsPath)) {
      return functionsPath;
    }
  }

  return null;
}

/**
 * Check if document is a bash/shell script
 */
function isBashDocument(document: TextDocument): boolean {
  if (document.languageId === 'shellscript') {
    return true;
  }

  // Check shebang for bash
  if (document.lineCount > 0) {
    const firstLine = document.lineAt(0).text;
    if (firstLine.startsWith('#!') && firstLine.includes('bash')) {
      return true;
    }
  }

  // Check file extension
  const ext = path.extname(document.uri.fsPath);
  return ['.sh', '.bash'].includes(ext);
}

/**
 * Update status bar with MAINFRAME status
 */
function updateStatusBar(): void {
  if (!statusBar) {
    return;
  }

  const enabled = workspace.getConfiguration('mainframe').get<boolean>('enable', true);

  if (!enabled) {
    statusBar.text = '$(circle-slash) MAINFRAME: Disabled';
    statusBar.tooltip = 'MAINFRAME LSP is disabled. Click to enable.';
    statusBar.backgroundColor = undefined;
    return;
  }

  const functionsPath = getFunctionsJsonPath();

  if (!functionsPath) {
    statusBar.text = '$(warning) MAINFRAME: Not Found';
    statusBar.tooltip = 'MAINFRAME installation not detected. Set mainframe.functionsPath in settings.';
    statusBar.backgroundColor = new ThemeColor('statusBarItem.warningBackground');
    return;
  }

  if (client && client.state === 2) { // Running
    statusBar.text = '$(check) MAINFRAME';
    statusBar.tooltip = `MAINFRAME LSP active\nFunctions: ${functionsPath}`;
    statusBar.backgroundColor = undefined;
  } else {
    statusBar.text = '$(sync~spin) MAINFRAME: Starting...';
    statusBar.tooltip = 'MAINFRAME LSP is starting...';
    statusBar.backgroundColor = undefined;
  }
}

/**
 * Create and start the language client
 */
async function startLanguageClient(context: ExtensionContext): Promise<void> {
  const enabled = workspace.getConfiguration('mainframe').get<boolean>('enable', true);

  if (!enabled) {
    console.log('[MAINFRAME] Extension is disabled');
    updateStatusBar();
    return;
  }

  const functionsPath = getFunctionsJsonPath();

  if (!functionsPath) {
    window.showWarningMessage(
      'MAINFRAME installation not detected. Please set mainframe.functionsPath in settings.',
      'Open Settings'
    ).then(selection => {
      if (selection === 'Open Settings') {
        commands.executeCommand('workbench.action.openSettings', 'mainframe.functionsPath');
      }
    });
    updateStatusBar();
    return;
  }

  // Server module path
  const serverModule = context.asAbsolutePath(path.join('out', 'server.js'));

  if (!fs.existsSync(serverModule)) {
    window.showErrorMessage(
      `MAINFRAME LSP server not found at ${serverModule}. Please rebuild the extension.`
    );
    return;
  }

  // Debug options for server
  const debugOptions = { execArgv: ['--nolazy', '--inspect=6009'] };

  // Server options
  const serverOptions: ServerOptions = {
    run: {
      module: serverModule,
      transport: TransportKind.ipc,
      args: ['--functions-path', functionsPath],
    },
    debug: {
      module: serverModule,
      transport: TransportKind.ipc,
      options: debugOptions,
      args: ['--functions-path', functionsPath],
    },
  };

  // Client options
  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: 'file', language: 'shellscript' },
      { scheme: 'file', pattern: '**/*.sh' },
      { scheme: 'file', pattern: '**/*.bash' },
    ],
    synchronize: {
      fileEvents: workspace.createFileSystemWatcher('**/*.{sh,bash}'),
    },
    initializationOptions: {
      functionsPath,
      showHints: workspace.getConfiguration('mainframe').get<boolean>('showHints', true),
    },
  };

  // Create the language client
  client = new LanguageClient(
    'mainframe-bash-lsp',
    'MAINFRAME Bash Language Server',
    serverOptions,
    clientOptions
  );

  // Start the client
  try {
    await client.start();
    console.log('[MAINFRAME] Language server started successfully');
    updateStatusBar();
  } catch (error) {
    window.showErrorMessage(`Failed to start MAINFRAME LSP: ${error}`);
    console.error('[MAINFRAME] Failed to start language server:', error);
  }
}

/**
 * Stop the language client
 */
async function stopLanguageClient(): Promise<void> {
  if (client) {
    await client.stop();
    client = undefined;
    console.log('[MAINFRAME] Language server stopped');
    updateStatusBar();
  }
}

/**
 * Extension activation
 */
export async function activate(context: ExtensionContext): Promise<void> {
  console.log('[MAINFRAME] Extension activating...');

  // Create status bar item
  statusBar = window.createStatusBarItem(StatusBarAlignment.Right, 100);
  statusBar.command = 'mainframe.toggleEnable';
  statusBar.show();
  context.subscriptions.push(statusBar);

  // Initial status update
  updateStatusBar();

  // Register commands
  context.subscriptions.push(
    commands.registerCommand('mainframe.restart', async () => {
      await stopLanguageClient();
      await startLanguageClient(context);
      window.showInformationMessage('MAINFRAME LSP restarted');
    })
  );

  context.subscriptions.push(
    commands.registerCommand('mainframe.toggleEnable', async () => {
      const config = workspace.getConfiguration('mainframe');
      const currentValue = config.get<boolean>('enable', true);
      await config.update('enable', !currentValue, true);

      if (!currentValue) {
        await startLanguageClient(context);
      } else {
        await stopLanguageClient();
      }

      updateStatusBar();
    })
  );

  context.subscriptions.push(
    commands.registerCommand('mainframe.showFunctionsPath', () => {
      const functionsPath = getFunctionsJsonPath();
      if (functionsPath) {
        window.showInformationMessage(`FUNCTIONS.json: ${functionsPath}`);
      } else {
        window.showWarningMessage('MAINFRAME installation not detected');
      }
    })
  );

  context.subscriptions.push(
    commands.registerCommand('mainframe.openSettings', () => {
      commands.executeCommand('workbench.action.openSettings', '@ext:mainframe.bash-lsp');
    })
  );

  // Listen for configuration changes
  context.subscriptions.push(
    workspace.onDidChangeConfiguration(async (event) => {
      if (event.affectsConfiguration('mainframe')) {
        console.log('[MAINFRAME] Configuration changed, restarting server...');
        await stopLanguageClient();
        await startLanguageClient(context);
      }
    })
  );

  // Listen for active editor changes to update status bar
  context.subscriptions.push(
    window.onDidChangeActiveTextEditor((editor) => {
      if (editor && isBashDocument(editor.document)) {
        updateStatusBar();
      }
    })
  );

  // Start the language server
  await startLanguageClient(context);

  console.log('[MAINFRAME] Extension activated successfully');
}

/**
 * Extension deactivation
 */
export async function deactivate(): Promise<void> {
  console.log('[MAINFRAME] Extension deactivating...');
  await stopLanguageClient();

  if (statusBar) {
    statusBar.dispose();
    statusBar = undefined;
  }

  console.log('[MAINFRAME] Extension deactivated');
}
