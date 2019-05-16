module.exports = {
  development: {
    navServiceUrl: 'json(http://bb12a75a.ngrok.io/api/v1/portfolio).data',
    dataFeedAddress: '0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475',
  },
  ropsten: {
    navServiceUrl: '[STAGING URL]',
    dataFeedAddress: '',
  },
  mainnet: {
    navServiceUrl: '[PRODUCTION URL]',
    dataFeedAddress: '',
  },
};
