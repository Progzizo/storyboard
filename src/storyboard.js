/*!
 * Storyboard
 *
 * End-to-end, hierarchical, real-time, colorful logs and stories
 *
 * @copyright Guillermo Grau Panea 2016
 * @license MIT
 */

// Chalk is disabled by default in the browser. Override
// this default (we'll handle ANSI code conversion ourselves
// when needed)
import chalk from 'chalk';
import mainStory from './gral/stories';
import filters from './gral/filters';
import {
  init as hubInit,
  configure as hubConfigure,
  getPlugins, addPlugin, removePlugin, removeAllPlugins,
} from './gral/hub';

chalk.enabled = true;

hubInit({ mainStory });

const configure = (options = {}) => {
  Object.keys(options).forEach(key => {
    const val = options[key];
    switch (key) {
      case 'filter':
        filters.config(val);
        break;
      case 'bufSize':
        hubConfigure({ bufSize: val });
        break;
      default:
        break;
    }
  })
};

const gracefulExit = () => {
  mainStory.close();
  removeAllPlugins();
};
/* istanbul ignore next */
try {
  window.addEventListener('beforeunload', gracefulExit);
} catch (err) { /* ignore */ }
try {
  process.on('exit', gracefulExit);
} catch (err) { /* ignore */ }

// -------------------------------------
// API
// -------------------------------------
export {
  mainStory,
  chalk,
  configure,
  getPlugins, addPlugin, removePlugin, removeAllPlugins,
};
