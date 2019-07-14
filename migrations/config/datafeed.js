module.exports = {
  development: {
    navServiceUrl: 'json(https://api.solidityfund.now.sh/api/v1/portfolio).data',
    dataFeedAddress: '0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475',
  },
  ropsten: {
    navServiceUrl: 'json(http://0d7b80c1.ngrok.io/api/v1/portfolio).data',
    dataFeedAddress: '0xa0c93acce8fce9c15114cef6eb16d0ed1affaa61',
  },
  mainnet: {
    navServiceUrl: '[PRODUCTION URL]',
    dataFeedAddress: '',
  },
};
