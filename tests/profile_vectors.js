// Spočítá všechny vektory z tests/vectors/profile_validation.json pomocí JS kódu aplikace
// (src/jsonschema_mini.js + src/profile_core.js) a vypíše JSON pole výsledků na stdout.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..');
const schema = JSON.parse(fs.readFileSync(path.join(root, 'src/onboarding_schema.json'), 'utf8'));
const core = require(path.join(root, 'src/profile_core.js'));
const vectors = JSON.parse(fs.readFileSync(path.join(root, 'tests/vectors/profile_validation.json'), 'utf8'));
const out = vectors.map((v) => {
  switch (v.kind) {
    case 'validate': return core.validateDoc(schema, v.doc, v.root);
    case 'incomplete': return core.incomplete(v.doc, v.root);
    case 'derive': return core.applyDerived(v.doc);
    case 'trim': return core.trimDeep(v.doc);
    case 'target': return core.goalTarget(v.b, v.bp);
    default: throw new Error('neznámý druh vektoru ' + v.kind);
  }
});
process.stdout.write(JSON.stringify(out));
