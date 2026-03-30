(() => {
  const searchInput = document.getElementById('search-input');
  const venueButtons = document.querySelectorAll('.venue-btn');
  let activeVenue = 'all';

  function applyFilters() {
    const query = searchInput.value.toLowerCase().trim();

    document.querySelectorAll('.date-section').forEach(section => {
      let sectionHasVisible = false;

      section.querySelectorAll('.event-card').forEach(card => {
        const venueMatch = activeVenue === 'all' || card.dataset.venue === activeVenue;
        const searchMatch = !query
          || card.dataset.name.includes(query)
          || card.dataset.venue.includes(query)
          || card.dataset.tags.includes(query);

        const visible = venueMatch && searchMatch;
        card.style.display = visible ? '' : 'none';
        if (visible) sectionHasVisible = true;
      });

      section.style.display = sectionHasVisible ? '' : 'none';
    });
  }

  searchInput.addEventListener('input', applyFilters);

  venueButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      venueButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      activeVenue = btn.dataset.venue;
      applyFilters();
    });
  });
})();
