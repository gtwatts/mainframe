// Test file with secure patterns
const apiKey = process.env.API_KEY;

function getUser(req, res) {
    const { id } = req.params;
    const sanitizedId = parseInt(id, 10);
    if (isNaN(sanitizedId)) return res.status(400).json({ error: 'Invalid ID' });

    const user = await db.query('SELECT id, name, email FROM users WHERE id = $1', [sanitizedId]);
    const { password, salt, ...safeUser } = user;
    res.json(safeUser);
}

function renderContent(text) {
    const escaped = escapeHtml(text);
    element.textContent = escaped;
}
