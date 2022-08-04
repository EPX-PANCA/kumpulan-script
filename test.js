<script>
  if(localStorage.getItem("theme")==undefined){
    localStorage.setItem("theme","dark");
    (document.querySelector("html").className="dark-mode");
  }else{
    console.log("false");
  }
</script>
