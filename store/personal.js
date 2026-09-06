export const state = () => ({ playback: null, syncState: 'synced', importCount: 0 })
export const mutations = { update(state, value) { Object.assign(state, value) } }
