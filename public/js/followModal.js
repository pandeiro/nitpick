// @license http://www.gnu.org/licenses/licenses/agpl-3.0.html AGPL-3.0
// SPDX-License-Identifier: AGPL-3.0-only

function openFollowModal() {
    const modal = document.getElementById('follow-modal');
    if (modal) {
        modal.classList.add('show');
    }
}

function closeFollowModal() {
    const modal = document.getElementById('follow-modal');
    if (modal) {
        modal.classList.remove('show');
    }
}

document.addEventListener('click', function(e) {
    const modal = document.getElementById('follow-modal');
    if (modal && e.target === modal) {
        closeFollowModal();
    }
});

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closeFollowModal();
    }
});
// @license-end
