import fs from 'node:fs';
import {validateBytes} from 'gltf-validator';
const results = [];
for (const file of fs.readdirSync('models').filter(file => file.endsWith('.glb'))) {
  const value = await validateBytes(new Uint8Array(fs.readFileSync(`models/${file}`)), {uri: file});
  results.push({file, errors: value.issues.numErrors, warnings: value.issues.numWarnings, messages: value.issues.messages});
}
fs.writeFileSync('review/validation.json', JSON.stringify(results, null, 2));
console.log(JSON.stringify({models: results.length, errors: results.reduce((sum, item) => sum + item.errors, 0), warnings: results.reduce((sum, item) => sum + item.warnings, 0)}));
if (results.some(item => item.errors > 0)) process.exitCode = 1;
