// Injecte le lien "Fusionner" dans le menu "..." de la demande Redmine.
document.addEventListener('DOMContentLoaded', function () {
  var template = document.getElementById('merge-drdn-item');
  if (!template) return;

  var dropdown = document.querySelector('.contextual .drdn .drdn-items');
  if (!dropdown) return;

  dropdown.appendChild(template.content.cloneNode(true));
});
