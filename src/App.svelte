<script>
  import { quotes } from "./lib/quotes";
  import { onMount } from "svelte";
  import "./lib/styles.scss";

  let quote = "hi";
  let author = "hi";
  let real = false;

  let score = 0;

  let game = false;
  let failed = false;

  let highscore;

  onMount(() => {
    if (localStorage.getItem("highscore")) {
      highscore = localStorage.getItem("highscore");
    } else {
      localStorage.setItem("highscore", 0);
    }
  });

  function getRandomInt(min, max) {
    min = Math.ceil(min);
    max = Math.floor(max);
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  function setQuote() {
    const selectedQuote = quotes[getRandomInt(0, quotes.length - 1)];
    quote = selectedQuote.quote;
    author = selectedQuote.author;
    real = selectedQuote.real;
  }
  setQuote();

  function checkQuote(input) {
    if (input == real) {
      score++;
    } else {
      if (score > highscore) {
        highscore = score;
        localStorage.setItem("highscore", score);
      }
      failed = true;
      score = 0;
    }
    setQuote();
  }
</script>

<main id="main">
  <img src="./src/assets/QuotasWhite.png" height="100" alt="QuotasWhite.png">
  <br /><br />
  <h2>Puntuación más alta: {highscore} 🌟</h2>
  {#if game && !failed}
    <h2>🏆 Puntuación actual: {score} 🏆</h2>
    <div id="quote">
      <p>"{quote}"</p>
      <h3>-{author}</h3>
      <div id="buttons">
        <button
          on:click={() => {
            checkQuote(true);
          }}
          class="real">✓ Cita real</button
        >
        <button
          on:click={() => {
            checkQuote(false);
          }}
          class="fake">✕ Cita falsa</button
        >
      </div>
    </div>
  {:else if failed}
    <p>😥 Uh! Te has equivocado, era lo contrario.</p>
    <button
      on:click={() => {
        failed = false;
      }}>¿Probar de nuevo?</button
    >
  {:else}
    <p id="description">
      Bienvenidos a Citas celebres. Un juego muy sencillo para ganar experiencia
      en el mundo. <br /><br />
      <strong>¿Adivinarás si es una cita celebre real o de ChatGPT?</strong>
    </p>
    <button on:click={() => {game = true;}}>Jugar ▶</button>
  {/if}
</main>
