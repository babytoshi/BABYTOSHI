// SPDX-License-Identifier: MIT

//
// $BabyToshi proposes an innovative feature in its contract.
//
// DIVIDEND YIELD PAID IN BTCB! With the auto-claim feature,
// simply hold$BabyToshi and you'll receive BTCB automatically in your wallet.
// 
// Hold minimum 200'000 BabyToshi to become top holder and get rewarded in Binance-Bitcoin on every transaction !
// 7% of rewards, 4% liquidity pool, 4% marketing | 15% tax

// If you missed BabyCake, Checoin or BabyAda before their 100 000% take off … Don't miss BabyToshi this time !
//

pragma solidity ^0.6.2;

import "./BABYTOSHIDividendTracker.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./IPancakeSwapV2Pair.sol";
import "./IPancakeSwapV2Factory.sol";
import "./IPancakeSwapV2Router.sol";

contract BABYTOSHI is ERC20, Ownable {
    using SafeMath for uint256;

    string private _NAME = "BabyToshi";
    string private _SYMBOL = "BABYTOSHI";
    uint256 private _TOTAL_SUPPLY = 10_000_000_000; // 10 billion

    //Anti-Whale System
    uint256 private _MAX_WALLET = 150_000_000;

    IPancakeSwapV2Router02 public uniswapV2Router;
    address public  pancakeswapV2Pair;

    bool private swapping;

    //TEAM
    address public _marketingWalletAddress = 0x61472CEd7D1Dea15d3Ef3e30158006a4152E48b5; // Marketing wallet address
        
    //DIVIDENDS
    BABYTOSHIDividendTracker public dividendTracker;

    address public immutable BTCB = address(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c); // BTCB address
    address public _pancakeswapRouterAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // PancakeSwap routeraddress
    
    address public deadWallet = 0x000000000000000000000000000000000000dEaD; // Dead wallet

    uint256 public swapTokensAtAmount = 2_000_000 * (10**18);
    
    uint256 public maxWalletTokens =  _MAX_WALLET * (10**18);

    mapping(address => bool) public _isBlacklisted;

    uint256 public BTCBRewardsFee = 7;
    uint256 public liquidityFee = 4;
    uint256 public marketingFee = 4;
    uint256 public totalFees = BTCBRewardsFee.add(liquidityFee).add(marketingFee);

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300_000;

     // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;


    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdatePancakeSwapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(
    	uint256 tokensSwapped,
    	uint256 amount
    );

    event ProcessedDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );

    constructor() public ERC20(_NAME, _SYMBOL) {
    	dividendTracker = new BABYTOSHIDividendTracker();

    	IPancakeSwapV2Router02 _uniswapV2Router = IPancakeSwapV2Router02(_pancakeswapRouterAddress);
         // Create a uniswap pair for this new token
        address _pancakeswapV2Pair = IPancakeSwapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        pancakeswapV2Pair = _pancakeswapV2Pair;

        _setAutomatedMarketMakerPair(_pancakeswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(deadWallet);
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(_marketingWalletAddress, true);
        excludeFromFees(address(this), true);

        // create de contract creation
        _mint(owner(), _TOTAL_SUPPLY * (10**18));
        //Send tokens to team
    }

    receive() external payable {

  	}

    function updateDividendTracker(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "BABYTOSHI: The dividend tracker already has that address");

        BABYTOSHIDividendTracker newDividendTracker = BABYTOSHIDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "BABYTOSHI: The new dividend tracker must be owned by the BABYTOSHI token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updatePancakeSwapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "BABYTOSHI: The router already has that address");
        emit UpdatePancakeSwapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IPancakeSwapV2Router02(newAddress);
        address _pancakeswapV2Pair = IPancakeSwapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        pancakeswapV2Pair = _pancakeswapV2Pair;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "BABYTOSHI: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setMarketingWallet(address payable wallet) external onlyOwner{
        _marketingWalletAddress = wallet;
    }

    function setBTCBRewardsFee(uint256 value) external onlyOwner{
        BTCBRewardsFee = value;
        totalFees = BTCBRewardsFee.add(liquidityFee).add(marketingFee);
    }

    function setLiquiditFee(uint256 value) external onlyOwner{
        liquidityFee = value;
        totalFees = BTCBRewardsFee.add(liquidityFee).add(marketingFee);
    }

    function setMarketingFee(uint256 value) external onlyOwner{
        marketingFee = value;
        totalFees = BTCBRewardsFee.add(liquidityFee).add(marketingFee);
    }

    function setMaxWallet(uint256 amount) public onlyOwner {
        //MAXIMUM 5% of the total supply
        require(amount <= _TOTAL_SUPPLY.div(20), "The max wallet is to higher");
        maxWalletTokens = amount * 10**18;
    }

    function removeMaxWallet() public onlyOwner {
        maxWalletTokens = _TOTAL_SUPPLY * 10**18;
    }

    function resetMaxWallet() public onlyOwner {
        maxWalletTokens = _MAX_WALLET * 10**18;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != pancakeswapV2Pair, "BABYTOSHI: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }
    
    function blacklistAddress(address account, bool value) external onlyOwner{
        _isBlacklisted[account] = value;
    }


    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "BABYTOSHI: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }


    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "BABYTOSHI: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "BABYTOSHI: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
  	}

	function dividendTokenBalanceOf(address account) public view returns (uint256) {
		return dividendTracker.balanceOf(account);
	}

	function excludeFromDividends(address account) external onlyOwner{
	    dividendTracker.excludeFromDividends(account);
	}

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

	function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
		dividendTracker.processAccount(msg.sender, false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }


    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlacklisted[from] && !_isBlacklisted[to], 'Blacklisted address');

        if (
            from != owner() &&
            to != owner() &&
            to != address(0xdead) &&
            to != pancakeswapV2Pair
        ) {
            uint256 contractBalanceRecepient = balanceOf(to);
            require(contractBalanceRecepient + amount <= maxWalletTokens, "Exceeds maximum wallet token amount.");
        }

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

		uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if( canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner()
        ) {
            swapping = true;

            uint256 marketingTokens = contractTokenBalance.mul(marketingFee).div(totalFees);
            swapAndSendToFee(marketingTokens);

            uint256 swapTokens = contractTokenBalance.mul(liquidityFee).div(totalFees);
            swapAndLiquify(swapTokens);

            uint256 sellTokens = balanceOf(address(this));
            swapAndSendDividends(sellTokens);

            swapping = false;
        }


        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if(takeFee) {
        	uint256 fees = amount.mul(totalFees).div(100);
        	if(automatedMarketMakerPairs[to]){
        	    fees += amount.mul(1).div(100);
        	}
        	amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping) {
	    	uint256 gas = gasForProcessing;

	    	try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	}
	    	catch {

	    	}
        }
    }

    function swapAndSendToFee(uint256 tokens) private  {

        uint256 initialBTCBBalance = IERC20(BTCB).balanceOf(address(this));

        swapTokensForCake(tokens);
        uint256 newBalance = (IERC20(BTCB).balanceOf(address(this))).sub(initialBTCBBalance);
        IERC20(BTCB).transfer(_marketingWalletAddress, newBalance);
    }

    function swapAndLiquify(uint256 tokens) private {
       // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }


    function swapTokensForEth(uint256 tokenAmount) private {


        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

    }

    function swapTokensForCake(uint256 tokenAmount) private {

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = BTCB;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );

    }

    function swapAndSendDividends(uint256 tokens) private{
        swapTokensForCake(tokens);
        uint256 dividends = IERC20(BTCB).balanceOf(address(this));
        bool success = IERC20(BTCB).transfer(address(dividendTracker), dividends);

        if (success) {
            dividendTracker.distributeBTCBDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }
}