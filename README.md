<!-- markdownlint-disable -->
<div align="center">
  <img src="./docs/images/origami.svg" height="128">
</div>
<div align="center">
  <br />
  <!-- markdownlint-restore -->

  <a href="https://twitter.com/dojostarknet">
    <img src="https://img.shields.io/twitter/follow/dojostarknet?style=social"/>
  </a>
  <a href="https://github.com/dojoengine/dojo">
    <img src="https://img.shields.io/github/stars/dojoengine/dojo?style=social"/>
  </a>

[![discord](https://img.shields.io/badge/join-dojo-green?logo=discord&logoColor=white)](https://discord.gg/PwDa2mKhR4)
![Github Actions][gha-badge] [![Telegram Chat][tg-badge]][tg-url]

[gha-badge]: https://img.shields.io/github/actions/workflow/status/dojoengine/dojo/ci.yml?branch=main
[tg-badge]: https://img.shields.io/endpoint?color=neon&logo=telegram&label=chat&style=flat-square&url=https%3A%2F%2Ftg.sumanjay.workers.dev%2Fdojoengine
[tg-url]: https://t.me/dojoengine

</div>

# Origami

Origami is a collection of essential primitives designed to facilitate the development of onchain games using the Dojo engine.
It provides a set of powerful tools and libraries that enable game developers to create complex, engaging, and efficient fully onchain games.

> _The magic of origami is in seeing a single piece of cairo evolve into a masterpiece through careful folds_
>
> <p align="right">Sensei</p>

<div align="center">
  <img src="./docs/videos/usage.gif" height="400">
</div>

---

### Crates

- [Algebra](./crates/algebra)
- [Defi](./crates/defi/)
- [Map](./crates/map)
- Physics (WIP)
- [Random](./crates/random)
- [Rating](./crates/rating)
- [Security](./crates/security)

### Easy integration into your project

Incorporate `origami` seamlessly into your projects using Scarb.toml.

Add the following to your `[dependencies]`:

```toml
[dependencies]
origami_random = { git = "https://github.com/dojoengine/origami" }
origami_map = { git = "https://github.com/dojoengine/origami" }
```

Now you will be able to use origami like any other Cairo package!

### 🏗️ Join Our Contributors

Your expertise can shape the future of game development! We're actively seeking contributions.

### ❓ Dedicated Support

Run into a snag? Reach out on our [GitHub Issues](https://github.com/dojoengine/origami/issues) or join the conversation in our [Discord community](https://discord.gg/dojoengine) for tailored assistance and vibrant discussions.
