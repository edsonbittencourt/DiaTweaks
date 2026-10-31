const SECTIONS = ['What', 'Why', 'Proof', 'Tested on', 'Checklist'];
const MEDIA = /!\[[^\]]*\]\([^)]+\)|<img\s|<video\s|https:\/\/github\.com\/user-attachments\/assets\/[\w-]+|\.(png|jpe?g|gif|mp4|mov|webm)\b/i;
const CONVENTIONAL = /^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([\w-]+\))?!?: \S.{0,70}$/;
const ATTRIBUTION = /^(co-authored-by:.*\b(claude|copilot|chatgpt|openai|anthropic|gemini|cursor|codex)\b|.*generated (with|by) .*(claude|copilot|chatgpt|ai\b))/im;
const SLOP = /\b(comprehensive|robust|seamless(ly)?|leverag(e|es|ing)|delve|holistic|this pr introduces)\b/i;
const MAX_WORDS = 250;

function sections(body) {
  const text = body.replace(/<!--[\s\S]*?-->/g, '');
  const found = {};
  for (const part of text.split(/^##\s+/m).slice(1)) {
    const [heading, ...rest] = part.split('\n');
    found[heading.trim()] = rest.join('\n').trim();
  }
  return found;
}

function check({ body, files, commits }) {
  const problems = [];
  const found = sections(body || '');
  for (const name of SECTIONS) if (!found[name]) problems.push(`Fill in the "## ${name}" section.`);
  for (const item of (found.Checklist || '').match(/^- \[ \] .+$/gm) || []) problems.push(`Tick the checklist: "${item.slice(6)}".`);
  if (files.some((f) => f.startsWith('src/dylib/')) && !MEDIA.test(found.Proof || ''))
    problems.push('This changes what Dia looks like: add a screenshot (or a screen recording if it animates) under "## Proof".');

  const prose = Object.entries(found).filter(([k]) => k !== 'Proof').map(([, v]) => v).join(' ');
  const words = prose.replace(/https?:\/\/\S+/g, '').split(/\s+/).filter(Boolean).length;
  if (words > MAX_WORDS) problems.push(`Keep the description under ${MAX_WORDS} words (it has ${words}).`);
  const slop = prose.match(SLOP);
  if (slop) problems.push(`Rewrite in plain words: "${slop[0]}".`);

  for (const { sha, message } of commits) {
    const subject = message.split('\n')[0];
    if (!CONVENTIONAL.test(subject)) problems.push(`${sha.slice(0, 7)}: use a Conventional Commit subject ("fix(dylib): …"), got "${subject}".`);
    if (ATTRIBUTION.test(message)) problems.push(`${sha.slice(0, 7)}: remove the AI attribution trailer.`);
  }
  return problems;
}

module.exports = async ({ github, context, core }) => {
  const pr = context.payload.pull_request;
  const params = { owner: context.repo.owner, repo: context.repo.repo, pull_number: pr.number, per_page: 100 };
  const files = (await github.paginate(github.rest.pulls.listFiles, params)).map((f) => f.filename);
  const commits = (await github.paginate(github.rest.pulls.listCommits, params)).map((c) => ({ sha: c.sha, message: c.commit.message }));
  const problems = check({ body: pr.body, files, commits });
  if (problems.length) core.setFailed(problems.map((p) => `- ${p}`).join('\n'));
};

module.exports.check = check;
