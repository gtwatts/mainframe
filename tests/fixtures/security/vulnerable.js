// Test file with intentional security vulnerabilities for scanner testing
const API_KEY = "sk-proj-1234567890abcdefghijklmnop";
const password = "super_secret_123";
const secret = "ghp_abcdefghijklmnopqrstuvwxyz1234567890";

function getUser(req, res) {
    const query = "SELECT * FROM users WHERE id = " + req.params.id;
    db.execute(query);

    const name = req.body.username;
    document.innerHTML = "<div>" + name + "</div>";

    res.json(user);
}

function runCommand(input) {
    const cmd = "ls " + input;
    exec(cmd);
    subprocess.call(cmd, shell=True);
}

function login(username, password) {
    const hash = md5(password);
    session.sid = generateId();
}

app.post('/upload', (req, res) => {
    const file = req.files.upload;
    file.mv('/public/uploads/' + file.name);
});

app.get('/api/users', (req, res) => {
    const users = db.find();
    res.send(users);
});
