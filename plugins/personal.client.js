import { registerPlugin, Capacitor } from '@capacitor/core'
import { App } from '@capacitor/app'
import { AbsAudioPlayer } from '@/plugins/capacitor'

export const AbsPersonal = registerPlugin('AbsPersonal')

export default ({ store, app }) => {
  if (Capacitor.getPlatform() !== 'ios') return
  let action = '', refreshing = false
  const dispatchAction = async () => {
    if (!action) return
    if (action === 'import') { action = ''; await app.router.push('/import').catch(() => {}); return }
    const playback = store.state.personal.playback
    if (!playback?.id || (!playback.id.startsWith('local_') && store.state.user.serverConnectionConfig?.id !== playback.serverId)) return
    action = ''
    await app.router.push('/bookshelf').catch(() => {})
    await AbsAudioPlayer.prepareLibraryItem({ libraryItemId: playback.id, episodeId: playback.episodeId || null, playWhenReady: true, playbackRate: store.state.user.settings.playbackRate || 1 })
  }
  const refresh = async () => {
    if (refreshing) return
    refreshing = true
    try {
      const { playback, syncState } = await AbsPersonal.getPlayback()
      store.commit('personal/update', { playback, syncState })
      const { files } = await AbsPersonal.listImports()
      store.commit('personal/update', { importCount: files.length })
      const pending = await AbsPersonal.takeAction()
      action = pending.action || action
      await dispatchAction()
    } catch (error) { console.warn('Personal integration:', error.message) }
    finally { refreshing = false }
  }
  AbsPersonal.addListener('syncState', ({ state }) => store.commit('personal/update', { syncState: state }))
  App.addListener('appStateChange', ({ isActive }) => { if (isActive) refresh() })
  App.addListener('appUrlOpen', ({ url }) => { if (url.startsWith('chaoaudiobook://') || url.startsWith('file://')) refresh() })
  store.watch((state) => state.user.serverConnectionConfig?.id, () => refresh())
  setTimeout(refresh, 1000)
  setInterval(refresh, 30000)
}
