(() => {
  window.__ready = true;
  const root = document.documentElement;
  if (!window.gsap || !window.ScrollTrigger) {
    root.classList.remove("js");
    return;
  }
  gsap.registerPlugin(ScrollTrigger, SplitText);

  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = matchMedia("(pointer: fine)").matches;
  const $ = (selector, scope = document) => scope.querySelector(selector);
  const $$ = (selector, scope = document) => [...scope.querySelectorAll(selector)];

  /** Prepares SVG strokes for a "draw on" animation and returns the elements. */
  function drawable(elements) {
    elements.forEach((el) => {
      const length = el.getTotalLength ? el.getTotalLength() : 400;
      gsap.set(el, { strokeDasharray: length, strokeDashoffset: length });
    });
    return elements;
  }

  // ---------- Smooth scroll ----------
  let lenis = null;
  if (!reduceMotion && window.Lenis) {
    lenis = new Lenis({ lerp: 0.09, wheelMultiplier: 1 });
    lenis.on("scroll", ScrollTrigger.update);
    gsap.ticker.add((time) => lenis.raf(time * 1000));
    gsap.ticker.lagSmoothing(0);
  }
  $$('a[href^="#"]').forEach((link) => {
    link.addEventListener("click", (event) => {
      const target = $(link.getAttribute("href"));
      if (!target) return;
      event.preventDefault();
      lenis ? lenis.scrollTo(target, { duration: 1.4 }) : target.scrollIntoView({ behavior: "smooth" });
    });
  });

  if (reduceMotion) {
    $(".preloader")?.remove();
    fitScreenToPhoto();
    ScrollTrigger.refresh();
    return;
  }

  // ---------- Preloader ----------
  function playPreloader() {
    const preloader = $(".preloader");
    const count = $(".preloader__count span");
    lenis?.stop();
    const progress = { value: 0 };
    const glyph = $$(".preloader__glyph use, .preloader__glyph path");
    gsap.set(glyph, { strokeDasharray: 400, strokeDashoffset: 400 });
    return gsap
      .timeline()
      .to(glyph, { strokeDashoffset: 0, duration: 1.5, ease: "power2.inOut", stagger: 0.1 }, 0)
      .to(progress, {
        value: 100,
        duration: 1.6,
        ease: "power2.inOut",
        onUpdate: () => (count.textContent = Math.round(progress.value)),
      }, 0)
      .to(".preloader__glyph", { scale: 0.8, autoAlpha: 0, duration: 0.4, ease: "power2.in" }, 1.7)
      .to(".preloader__count", { autoAlpha: 0, duration: 0.3 }, 1.7)
      .to(preloader, { yPercent: -100, duration: 0.9, ease: "expo.inOut" }, 1.9)
      .add(() => {
        preloader.remove();
        lenis?.start();
      });
  }

  // ---------- Hero ----------
  /** CSS matrix3d that maps a w×h box onto four points (perspective warp). */
  function quadMatrix(w, h, points) {
    const src = [[0, 0], [w, 0], [w, h], [0, h]];
    const a = [];
    const b = [];
    src.forEach(([x, y], i) => {
      const [u, v] = points[i];
      a.push([x, y, 1, 0, 0, 0, -u * x, -u * y]);
      b.push(u);
      a.push([0, 0, 0, x, y, 1, -v * x, -v * y]);
      b.push(v);
    });
    // Gaussian elimination for the 8 unknowns.
    for (let col = 0; col < 8; col++) {
      let pivot = col;
      for (let row = col + 1; row < 8; row++) if (Math.abs(a[row][col]) > Math.abs(a[pivot][col])) pivot = row;
      [a[col], a[pivot]] = [a[pivot], a[col]];
      [b[col], b[pivot]] = [b[pivot], b[col]];
      for (let row = 0; row < 8; row++) {
        if (row === col) continue;
        const factor = a[row][col] / a[col][col];
        for (let k = col; k < 8; k++) a[row][k] -= factor * a[col][k];
        b[row] -= factor * b[col];
      }
    }
    const [m0, m1, m2, m3, m4, m5, m6, m7] = b.map((value, i) => value / a[i][i]);
    return `matrix3d(${m0},${m3},0,${m6},${m1},${m4},0,${m7},0,0,1,0,${m2},${m5},0,1)`;
  }

  function fitScreenToPhoto() {
    // Display corners in the MacBook photo (percent of image width/height): TL, TR, BR, BL.
    const corners = [[13.171, 2.539], [88.146, 4.02], [85.951, 52.786], [13.306, 51.375]];
    const mac = $(".mac");
    const screen = $(".mac__screen");
    const apply = () => {
      const w = mac.offsetWidth;
      const h = mac.offsetHeight;
      const points = corners.map(([px, py]) => [(px / 100) * w - screen.offsetLeft, (py / 100) * h - screen.offsetTop]);
      screen.style.transform = quadMatrix(screen.offsetWidth, screen.offsetHeight, points);
    };
    apply();
    new ResizeObserver(apply).observe(mac);
  }

  function hero() {
    fitScreenToPhoto();
    const titleSplit = SplitText.create(".hero__line", { type: "chars", mask: "lines" });
    const welcomeSplit = SplitText.create(".hero__welcome", { type: "chars", mask: "lines" });
    const mac = $(".mac");
    const notchParts = $$(".notch__ring, .notch__glyph, .notch__check");

    gsap.set(notchParts, { xPercent: -50, x: 0 });
    gsap.set(".lockscreen", { autoAlpha: 1 });
    gsap.set(welcomeSplit.chars, { yPercent: 110 });

    // Zoom so the display fills the view, centred vertically (layout values ignore transforms).
    const screenCenter = () => mac.offsetTop + mac.offsetHeight * 0.28;
    const zoom = () => Math.min(1.3, (innerHeight * 0.66) / (mac.offsetHeight * 0.49), (innerWidth * 0.96) / (mac.offsetWidth * 0.75));
    const endScale = () => Math.min(1, (innerHeight * 0.6) / (mac.offsetHeight * 0.55));
    const welcomeBottom = () => $(".hero__welcome").offsetTop + $(".hero__welcome").offsetHeight + 24;

    // Intro after the preloader.
    const intro = gsap
      .timeline({ paused: true })
      .from(titleSplit.chars, { yPercent: 115, duration: 1.1, ease: "expo.out", stagger: 0.022 })
      .from(".hero__eyebrow", { y: 20, autoAlpha: 0, duration: 0.8, ease: "power3.out" }, 0.2)
      .from(mac, { y: 160, autoAlpha: 0, duration: 1.4, ease: "expo.out" }, 0.3)
      .from(".hero__scroll", { autoAlpha: 0, duration: 0.8 }, 0.9);

    // The spinning scan arc runs on its own clock.
    gsap.to(".notch__arc", { rotation: 360, svgOrigin: "50 50", duration: 1.1, ease: "none", repeat: -1 });

    // Scroll: wake the screen, zoom in, scan, blink, unlock, welcome back.
    gsap
      .timeline({
        defaults: { ease: "none" },
        scrollTrigger: { trigger: ".hero", start: "top top", end: "+=280%", scrub: 1, pin: true, anticipatePin: 1, invalidateOnRefresh: true },
      })
      .to([".hero__title", ".hero__eyebrow"], { yPercent: -40, autoAlpha: 0, duration: 1.8 }, 0)
      .to(".hero__scroll", { autoAlpha: 0, duration: 0.6 }, 0)
      .to(mac, { y: () => innerHeight / 2 - screenCenter(), scale: zoom, duration: 2.6, ease: "power2.inOut" }, 0)
      .to(".mac__off", { autoAlpha: 0, duration: 0.9 }, 1.4)
      .to(".notch", { width: "34%", height: "44%", borderRadius: "0 0 26px 26px", duration: 1.1, ease: "power3.inOut" }, 3.2)
      .to(".notch__content", { autoAlpha: 1, duration: 0.5 }, 3.7)
      .to(".notch__text--scan", { autoAlpha: 0, duration: 0.3 }, 4.8)
      .to(".notch__text--blink", { autoAlpha: 1, duration: 0.3 }, 4.9)
      .to(".notch__glyph .eye", { scaleY: 0.1, duration: 0.25 }, 5.4)
      .to(".notch__glyph .eye", { scaleY: 1, duration: 0.25 }, 5.65)
      .to([".notch__glyph", ".notch__ring"], { autoAlpha: 0, scale: 0.8, duration: 0.5 }, 6.1)
      .to(".notch__check", { strokeDashoffset: 0, duration: 0.7, ease: "power2.out" }, 6.3)
      .to(".notch__text--blink", { autoAlpha: 0, duration: 0.3 }, 6.3)
      .to(".notch__text--done", { autoAlpha: 1, duration: 0.3 }, 6.4)
      .to(".notch__content", { autoAlpha: 0, duration: 0.4 }, 7.4)
      .to(".notch", { width: "12%", height: "4.4%", borderRadius: "0 0 10px 10px", duration: 0.9, ease: "power3.inOut" }, 7.6)
      .to(".lockscreen", { yPercent: -100, duration: 1.2, ease: "power2.inOut" }, 7.7)
      .fromTo(".banner", { xPercent: 120, autoAlpha: 0 }, { xPercent: 0, autoAlpha: 1, duration: 0.8, ease: "power3.out" }, 8.6)
      .to(mac, {
        y: () => welcomeBottom() - mac.offsetTop - mac.offsetHeight * 0.28 * (1 - endScale()),
        scale: endScale,
        duration: 1.6,
        ease: "power2.inOut",
      }, 8.1)
      .set(".hero__welcome", { visibility: "visible" }, 8.4)
      .to(welcomeSplit.chars, { yPercent: 0, duration: 0.9, stagger: 0.03, ease: "power3.out" }, 8.4)
      .to({}, { duration: 0.6 });

    return intro;
  }

  // ---------- Marquee (speeds up and skews with scroll velocity) ----------
  function marquee() {
    const loops = $$(".marquee__track").map((track, index) =>
      gsap.fromTo(track, { xPercent: index ? -50 : 0 }, { xPercent: index ? 0 : -50, duration: 30, ease: "none", repeat: -1 })
    );
    const skew = gsap.quickTo(".marquee__track", "skewX", { duration: 0.4, ease: "power3" });
    let boost = 0;
    ScrollTrigger.create({
      trigger: ".marquee",
      start: "top bottom",
      end: "bottom top",
      onUpdate: (self) => {
        const velocity = self.getVelocity() / 250;
        boost = Math.min(Math.abs(velocity), 8);
        skew(gsap.utils.clamp(-8, 8, -velocity * 1.4));
      },
    });
    gsap.ticker.add(() => {
      boost *= 0.93;
      loops.forEach((loop) => loop.timeScale(1 + boost));
      if (boost < 0.05) skew(0);
    });
  }

  // ---------- How it works (horizontal on desktop) ----------
  function howItWorks() {
    const track = $(".how__track");
    const steps = $$(".step");
    const lidSetup = () => gsap.set(".step__art--lid .lid", { rotation: 70, svgOrigin: "156 116" });
    const closeLid = (timeline, step) => {
      const lid = $(".lid", step);
      if (lid) timeline.to(lid, { rotation: 0, duration: 0.8 }, 0.3);
    };

    gsap.to(".step__art .pulse", { opacity: 0.25, duration: 0.8, ease: "sine.inOut", yoyo: true, repeat: -1 });
    gsap.to(".step__art--eye", {
      scaleY: 0.08, transformOrigin: "50% 50%", duration: 0.1, yoyo: true, repeat: -1, repeatDelay: 2.4, ease: "power1.in",
    });

    const mm = gsap.matchMedia();
    mm.add("(min-width: 761px)", () => {
      const distance = () => track.scrollWidth - window.innerWidth;
      const horizontal = gsap.to(track, {
        x: () => -distance(),
        ease: "none",
        scrollTrigger: {
          trigger: ".how",
          start: "top top",
          end: () => "+=" + distance(),
          pin: true,
          scrub: 1,
          invalidateOnRefresh: true,
        },
      });
      lidSetup();
      steps.forEach((step) => {
        const tl = gsap
          .timeline({ scrollTrigger: { trigger: step, containerAnimation: horizontal, start: "left 85%", end: "left 35%", scrub: true } })
          .from(step, { autoAlpha: 0.2, scale: 0.92, duration: 1 }, 0)
          .to(drawable($$(".draw", step)), { strokeDashoffset: 0, duration: 1, stagger: 0.1 }, 0);
        closeLid(tl, step);
      });
    });
    mm.add("(max-width: 760px)", () => {
      lidSetup();
      steps.forEach((step) => {
        const tl = gsap
          .timeline({ scrollTrigger: { trigger: step, start: "top 85%", end: "top 40%", scrub: true } })
          .from(step, { y: 60, autoAlpha: 0.2, duration: 1 }, 0)
          .to(drawable($$(".draw", step)), { strokeDashoffset: 0, duration: 1, stagger: 0.1 }, 0);
        closeLid(tl, step);
      });
    });
  }

  // ---------- Text reveals ----------
  function textReveals() {
    $$(".split").forEach((heading) => {
      SplitText.create(heading, {
        type: "lines",
        mask: "lines",
        autoSplit: true,
        onSplit: (self) =>
          gsap.from(self.lines, {
            yPercent: 110,
            duration: 1.2,
            ease: "expo.out",
            stagger: 0.1,
            scrollTrigger: { trigger: heading, start: "top 85%" },
          }),
      });
    });

    SplitText.create(".statement__text", {
      type: "words",
      autoSplit: true,
      onSplit: (self) =>
        gsap.fromTo(self.words, { opacity: 0.14 }, {
          opacity: 1,
          ease: "none",
          stagger: 0.1,
          scrollTrigger: { trigger: ".statement", start: "top 70%", end: "bottom 60%", scrub: true },
        }),
    });

    const cta = SplitText.create(".cta__line", { type: "chars", mask: "lines" });
    gsap.from(cta.chars, {
      yPercent: 115,
      duration: 1.1,
      ease: "expo.out",
      stagger: 0.025,
      scrollTrigger: { trigger: ".cta", start: "top 70%" },
    });
    gsap.from([".cta__button", ".cta__meta"], {
      y: 40, autoAlpha: 0, duration: 1, ease: "power3.out", stagger: 0.1,
      scrollTrigger: { trigger: ".cta", start: "top 55%" },
    });
    gsap.from(".privacy__note", {
      y: 30, autoAlpha: 0, duration: 1, ease: "power3.out",
      scrollTrigger: { trigger: ".privacy__note", start: "top 90%" },
    });
    gsap.from(".color__lead, .swatch", {
      y: 30, autoAlpha: 0, duration: 0.9, ease: "power3.out", stagger: 0.05,
      scrollTrigger: { trigger: ".color", start: "top 70%" },
    });
    gsap.from(".color__demo", {
      scale: 0.85, autoAlpha: 0, rotate: -4, duration: 1.4, ease: "expo.out",
      scrollTrigger: { trigger: ".color", start: "top 70%" },
    });
  }

  // ---------- Feature cards: staggered entry + 3D tilt ----------
  function features() {
    ScrollTrigger.batch(".card", {
      start: "top 88%",
      onEnter: (batch) =>
        gsap.fromTo(batch, { y: 90, autoAlpha: 0, rotateX: -14 }, {
          y: 0, autoAlpha: 1, rotateX: 0, duration: 1.1, ease: "expo.out", stagger: 0.09, overwrite: true,
        }),
    });
    gsap.set(".card", { autoAlpha: 0, transformPerspective: 900 });

    if (!finePointer) return;
    $$(".tilt").forEach((card) => {
      const rotateX = gsap.quickTo(card, "rotateX", { duration: 0.5, ease: "power3" });
      const rotateY = gsap.quickTo(card, "rotateY", { duration: 0.5, ease: "power3" });
      card.addEventListener("pointermove", (event) => {
        const box = card.getBoundingClientRect();
        const px = (event.clientX - box.left) / box.width;
        const py = (event.clientY - box.top) / box.height;
        rotateY((px - 0.5) * 10);
        rotateX((0.5 - py) * 10);
        card.style.setProperty("--mx", `${px * 100}%`);
        card.style.setProperty("--my", `${py * 100}%`);
      });
      card.addEventListener("pointerleave", () => {
        rotateX(0);
        rotateY(0);
      });
    });
  }

  // ---------- Accent color: the whole page follows ----------
  function colorPicker() {
    const swatches = $$(".swatch");
    swatches.forEach((swatch) => {
      swatch.addEventListener("click", () => {
        swatches.forEach((other) => {
          other.classList.toggle("is-active", other === swatch);
          other.setAttribute("aria-checked", String(other === swatch));
        });
        gsap.to(root, { "--accent": getComputedStyle(swatch).getPropertyValue("--c").trim(), duration: 0.7, ease: "power2.out" });
        gsap.fromTo(".pill", { scale: 0.96 }, { scale: 1, duration: 0.8, ease: "elastic.out(1, 0.4)" });
      });
    });

    gsap.to(".pill__arc", { rotation: 360, svgOrigin: "50 50", duration: 1.1, ease: "none", repeat: -1 });
    const label = $(".pill__label");
    const loop = gsap
      .timeline({ repeat: -1, repeatDelay: 0.6, paused: true })
      .set(label, { textContent: "Face ID" })
      .set(".pill__check", { strokeDashoffset: 100 })
      .fromTo([".pill__glyph", ".pill__ring"], { autoAlpha: 0, scale: 0.8 }, { autoAlpha: 1, scale: 1, duration: 0.5, ease: "back.out(2)", transformOrigin: "50% 50%" })
      .to(".pill__glyph", { scale: 0.94, duration: 0.3, yoyo: true, repeat: 3, ease: "sine.inOut" }, "+=0.2")
      .to([".pill__glyph", ".pill__ring"], { autoAlpha: 0, scale: 0.8, duration: 0.35 }, "+=0.2")
      .to(".pill__check", { strokeDashoffset: 0, duration: 0.5, ease: "power2.out" })
      .set(label, { textContent: "Unlocked" }, "<")
      .to(".pill__check", { autoAlpha: 0, duration: 0.3 }, "+=1.2")
      .set(".pill__check", { autoAlpha: 1, strokeDashoffset: 100 });
    ScrollTrigger.create({
      trigger: ".color",
      start: "top bottom",
      end: "bottom top",
      onToggle: (self) => (self.isActive ? loop.play() : loop.pause()),
    });
  }

  // ---------- Stats counters ----------
  function counters() {
    $$(".stat__num").forEach((el) => {
      const to = Number(el.dataset.count);
      const from = to === 0 ? 99 : 0;
      const suffix = el.dataset.suffix || "";
      const value = { n: from };
      el.textContent = from + suffix;
      gsap.to(value, {
        n: to,
        duration: to === 0 ? 1.8 : 1.4,
        ease: "power3.out",
        scrollTrigger: { trigger: el, start: "top 85%" },
        onUpdate: () => (el.textContent = Math.round(value.n) + suffix),
      });
    });
    gsap.from(".stat", {
      y: 50, autoAlpha: 0, duration: 1, ease: "power3.out", stagger: 0.1,
      scrollTrigger: { trigger: ".stats", start: "top 85%" },
    });
  }

  // ---------- Cursor, magnetic buttons, nav ----------
  function pointerEffects() {
    if (finePointer) {
      const cursor = $(".cursor");
      const x = gsap.quickTo(cursor, "x", { duration: 0.35, ease: "power3" });
      const y = gsap.quickTo(cursor, "y", { duration: 0.35, ease: "power3" });
      addEventListener("pointermove", (event) => {
        if (!cursor.dataset.shown) {
          cursor.dataset.shown = "1";
          gsap.set(cursor, { x: event.clientX, y: event.clientY });
          gsap.to(cursor, { opacity: 1, duration: 0.3 });
        }
        x(event.clientX);
        y(event.clientY);
      });
      $$("a, button").forEach((el) => {
        el.addEventListener("pointerenter", () => gsap.to(cursor, { scale: 3, duration: 0.3 }));
        el.addEventListener("pointerleave", () => gsap.to(cursor, { scale: 1, duration: 0.3 }));
      });

      $$(".magnetic").forEach((el) => {
        const mx = gsap.quickTo(el, "x", { duration: 0.4, ease: "power3" });
        const my = gsap.quickTo(el, "y", { duration: 0.4, ease: "power3" });
        el.addEventListener("pointermove", (event) => {
          const box = el.getBoundingClientRect();
          mx((event.clientX - box.left - box.width / 2) * 0.35);
          my((event.clientY - box.top - box.height / 2) * 0.35);
        });
        el.addEventListener("pointerleave", () => {
          gsap.to(el, { x: 0, y: 0, duration: 0.9, ease: "elastic.out(1, 0.35)" });
        });
      });
    }

    const showNav = gsap.from(".nav", { yPercent: -120, duration: 0.45, ease: "power2.out", paused: true }).progress(1);
    ScrollTrigger.create({
      start: "top top",
      end: "max",
      onUpdate: (self) => (self.direction === 1 && self.scroll() > 200 ? showNav.reverse() : showNav.play()),
    });
  }

  // ---------- Boot ----------
  document.fonts.ready.then(() => {
    const intro = hero();
    marquee();
    howItWorks();
    textReveals();
    features();
    colorPicker();
    counters();
    pointerEffects();
    ScrollTrigger.refresh();
    playPreloader().add(() => intro.play(), "-=0.5");
  });
})();
