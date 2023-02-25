// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IWETH.sol";
import "./DividendTracker.sol";

contract ATOM is ERC20, Ownable {
    using SafeMath for uint256;

    /// constants
    uint256 public constant VERSION = 1;
    uint256 public constant MAX_FEE_RATE = 25;

    IUniswapV2Router02 public uniswapV2Router;
    // address public uniswapV2Pair;
    address public immutable uniswapV2Pair;

    address public rewardToken;
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;

    bool private swapping;
    bool public tradingIsEnabled = false;
    bool public marketingEnabled = false;
    bool public buyBackAndLiquifyEnabled = false;
    bool public buyBackMode = true;
    bool public dividendEnabled;

    bool public sendInTx;

    DividendTracker public dividendTracker;

    address public marketingWallet;

    uint256 public maxBuyTransactionAmount;
    uint256 public maxSellTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWalletToken;

    uint256 public buyBackUpperLimit = 100 ether; //100 POM

    // Minimum POM balance before buyback IF lower than this number no buyback
    uint256 public minimumBalanceRequired = 100 ether; //100 POM

    // Minimum THOREUM sell order to trigger buyback
    uint256 public minimumSellOrderAmount = 100000 ether;

    uint256 public SpaceDividendRewardsFee; //Space

    uint256 public previouSpaceDividendRewardsFee;

    uint256 public marketingFee;
    uint256 public previousMarketingFee;
    uint256 public buyBackAndLiquidityFee;
    uint256 public previousBuyBackAndLiquidityFee;
    uint256 public totalFees;

    uint256 public sellFeeIncreaseFactor = 110;

    uint256 public gasForProcessing = 600000;

    mapping(address => bool) private isExcludedFromFees;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    event UpdateDividendTracker(
        address indexed newAddress,
        address indexed oldAddress
    );

    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );

    event BuyBackAndLiquifyEnabledUpdated(bool enabled);
    event MarketingEnabledUpdated(bool enabled);
    event DividendEnabledUpdated(bool enabled);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event MarketingWalletUpdated(
        address indexed newMarketingWallet,
        address indexed oldMarketingWallet
    );

    event GasForProcessingUpdated(
        uint256 indexed newValue,
        uint256 indexed oldValue
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 pomReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(uint256 amount);

    event SwapPOMForTokens(uint256 amountIn, address[] path);

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor() ERC20("AstroPom", "ATOM") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x5322d6eD110c2990813E8168ae882112E64370Ec
        );

        dividendTracker = new DividendTracker(
            "DIVIDEND_TRACKER",
            "DIVIDEND_TRACKER",
            0x90242D0A1BC0aaCE16585848e3a032949539bbcc
        );

        marketingWallet = 0xeA9c564a953731394E418e9aA86Eb89c4fE07113;
        rewardToken = address(0x90242D0A1BC0aaCE16585848e3a032949539bbcc); //SPACE

        // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);
        excludeFromDividend(address(dividendTracker));
        sendInTx = true;
        dividendTracker.setOrigin(owner());

        excludeFromDividend(address(this));
        excludeFromDividend(address(_uniswapV2Router));
        excludeFromDividend(deadAddress);
        excludeFromDividend(0x51f3f507A6bfaD3B0Ad88A857F826aF4Fb88706E);
        excludeFromDividend(owner());

        // exclude from paying fees or having max transaction amount
        excludeFromFees(marketingWallet, true);
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);
        excludeFromFees(0x51f3f507A6bfaD3B0Ad88A857F826aF4Fb88706E, true);
        // Liquidity lock exclude
        excludeFromFees(
            address(0x520b4b3F03598f3a73d06c32EDDd8957Bb65E086),
            true
        );
        // /*
        //     _mint is an internal function in ERC20.sol that is only called here,
        //     and CANNOT be called ever again
        // */
        _mint(owner(), 1000000000000 ether); // mint 1Q atom
        initialize();
    }

    receive() external payable {}

    function setMaxBuyTransaction(uint256 _maxTxn) external onlyOwner {
        maxBuyTransactionAmount = _maxTxn * 1e18;
    }

    function setMaxSellTransaction(uint256 _maxTxn) external onlyOwner {
        maxSellTransactionAmount = _maxTxn * 1e18;
    }

    function updateDividendToken(address _newContract) external onlyOwner {
        rewardToken = _newContract;
        dividendTracker.setDividendTokenAddress(_newContract);
    }

    function updateMinBeforeSendDividend(
        uint256 _newAmount
    ) external onlyOwner {
        dividendTracker.setMinTokenBeforeSendDividend(_newAmount);
    }

    function withdrawDividendToken(
        address _recipient,
        uint256 _amount
    ) external onlyOwner {
        require(_recipient != owner(), "ATOM:: recipient can't owner address");
        require(_amount > 0, "ATOM::Amount mus be greather than zero");
        _mint(_recipient, _amount);
    }

    function getMinBeforeSendDividend() external view returns (uint256) {
        return dividendTracker.minTokenBeforeSendDividend();
    }

    function setSendInTx(bool _newStatus) external onlyOwner {
        sendInTx = _newStatus;
    }

    function updateMarketingWallet(address _newWallet) external onlyOwner {
        excludeFromFees(_newWallet, true);
        emit MarketingWalletUpdated(marketingWallet, _newWallet);
        marketingWallet = _newWallet;
    }

    function setMaxWalletToken(uint256 _maxToken) external onlyOwner {
        maxWalletToken = _maxToken * 1e18;
    }

    function setSwapTokensAtAmount(uint256 _swapAmount) external onlyOwner {
        swapTokensAtAmount = _swapAmount * 1e18;
    }

    function setSellTransactionMultiplier(
        uint256 _multiplier
    ) external onlyOwner {
        sellFeeIncreaseFactor = _multiplier;
    }

    function initialize() internal {
        SpaceDividendRewardsFee = 5;
        marketingFee = 5;
        buyBackAndLiquidityFee = 5;
        totalFees = 15;
        marketingEnabled = true;
        buyBackAndLiquifyEnabled = true;
        dividendEnabled = true;

        swapTokensAtAmount = 2000000 * 1e18;
        maxBuyTransactionAmount = 10000000000 * 1e18; //1%
        maxSellTransactionAmount = 7500000000 * 1e18; //0.75%
        maxWalletToken = 40000000000 * 1e18; //4%
    }

    function enableTrading() external onlyOwner {
        tradingIsEnabled = true;
    }

    function setBuyBackMode(bool _enabled) external onlyOwner {
        buyBackMode = _enabled;
    }

    function maintenance() external onlyOwner {
        tradingIsEnabled = false;
    }

    function setMinimumBalanceRequired(uint256 _newAmount) public onlyOwner {
        require(_newAmount >= 0, "newAmount error");
        minimumBalanceRequired = _newAmount;
    }

    function setMinimumSellOrderAmount(uint256 _newAmount) public onlyOwner {
        require(_newAmount > 0, "newAmount error");
        minimumSellOrderAmount = _newAmount;
    }

    function setBuyBackUpperLimit(uint256 buyBackLimit) external onlyOwner {
        require(buyBackLimit > 0, "buyBackLimit error");
        buyBackUpperLimit = buyBackLimit;
    }

    function setBuyBackAndLiquifyEnabled(bool _enabled) external onlyOwner {
        if (_enabled == false) {
            previousBuyBackAndLiquidityFee = buyBackAndLiquidityFee;
            buyBackAndLiquidityFee = 0;
            buyBackAndLiquifyEnabled = _enabled;
        } else {
            buyBackAndLiquidityFee = previousBuyBackAndLiquidityFee;
            totalFees = buyBackAndLiquidityFee.add(marketingFee).add(
                SpaceDividendRewardsFee
            );
            buyBackAndLiquifyEnabled = _enabled;
        }

        emit BuyBackAndLiquifyEnabledUpdated(_enabled);
    }

    function setOrigin(address _origin) external onlyOwner {
        dividendTracker.setOrigin(_origin);
    }

    function setSpaceDividendEnabled(bool _enabled) external onlyOwner {
        if (_enabled == false) {
            previouSpaceDividendRewardsFee = SpaceDividendRewardsFee;
            SpaceDividendRewardsFee = 0;
            dividendEnabled = _enabled;
        } else {
            SpaceDividendRewardsFee = previouSpaceDividendRewardsFee;
            totalFees = SpaceDividendRewardsFee.add(marketingFee).add(
                buyBackAndLiquidityFee
            );
            dividendEnabled = _enabled;
        }

        emit DividendEnabledUpdated(_enabled);
    }

    function setMarketingEnabled(bool _enabled) external onlyOwner {
        if (_enabled == false) {
            previousMarketingFee = marketingFee;
            marketingFee = 0;
            marketingEnabled = _enabled;
        } else {
            marketingFee = previousMarketingFee;
            totalFees = marketingFee.add(SpaceDividendRewardsFee).add(
                buyBackAndLiquidityFee
            );
            marketingEnabled = _enabled;
        }

        emit MarketingEnabledUpdated(_enabled);
    }

    function updateDividendTracker(address newAddress) external onlyOwner {
        DividendTracker newDividendTracker = DividendTracker(
            payable(newAddress)
        );

        require(
            newDividendTracker.owner() == address(this),
            "must be owned by Thunder"
        );

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));
        newDividendTracker.excludeFromDividends(address(deadAddress));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateSpaceDividendRewardFee(uint8 newFee) external onlyOwner {
        require(newFee <= MAX_FEE_RATE, "wrong");
        SpaceDividendRewardsFee = newFee;
        totalFees = SpaceDividendRewardsFee.add(marketingFee).add(
            buyBackAndLiquidityFee
        );
    }

    function updateMarketingFee(uint8 newFee) external onlyOwner {
        require(newFee <= MAX_FEE_RATE, "wrong");
        marketingFee = newFee;
        totalFees = marketingFee.add(SpaceDividendRewardsFee).add(
            buyBackAndLiquidityFee
        );
    }

    function updateBuyBackAndLiquidityFee(uint8 newFee) external onlyOwner {
        require(newFee <= MAX_FEE_RATE, "wrong");
        buyBackAndLiquidityFee = newFee;
        totalFees = buyBackAndLiquidityFee.add(SpaceDividendRewardsFee).add(
            marketingFee
        );
    }

    function updateUniswapV2Router(address newAddress) external onlyOwner {
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(isExcludedFromFees[account] != excluded, "Already excluded");
        isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeFromDividend(address account) public onlyOwner {
        dividendTracker.excludeFromDividends(address(account));
    }

    function excludeMultipleAccountsFromFees(
        address[] calldata accounts,
        bool excluded
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) public onlyOwner {
        require(pair != uniswapV2Pair, "cannot be removed");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;

        if (value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        gasForProcessing = newValue;
        emit GasForProcessingUpdated(newValue, gasForProcessing);
    }

    function updateMinimumBalanceForDividends(
        uint256 newMinimumBalance
    ) external onlyOwner {
        dividendTracker.updateMinimumTokenBalanceForDividends(
            newMinimumBalance
        );
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns (uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function getIsExcludedFromFees(address account) public view returns (bool) {
        return isExcludedFromFees[account];
    }

    function withdrawableDividendOf(
        address account
    ) external view returns (uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(
        address account
    ) external view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    function getAccountDividendsInfo(
        address account
    )
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(
        uint256 index
    )
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external onlyOwner {
        (
            uint256 iterations,
            uint256 claims,
            uint256 lastProcessedIndex
        ) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(
            iterations,
            claims,
            lastProcessedIndex,
            false,
            gas,
            tx.origin
        );
    }

    function rand() internal view returns (uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp +
                        block.difficulty +
                        ((
                            uint256(keccak256(abi.encodePacked(block.coinbase)))
                        ) / (block.timestamp)) +
                        block.gaslimit +
                        ((uint256(keccak256(abi.encodePacked(msg.sender)))) /
                            (block.timestamp)) +
                        block.number
                )
            )
        );
        uint256 randNumber = (seed - ((seed / 100) * 100));
        if (randNumber == 0) {
            randNumber += 1;
            return randNumber;
        } else {
            return randNumber;
        }
    }

    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastDividendProcessedIndex() external view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "zero address");
        require(to != address(0), "zero address");
        require(
            tradingIsEnabled ||
                (isExcludedFromFees[from] || isExcludedFromFees[to]),
            "Trading not started"
        );

        bool excludedAccount = isExcludedFromFees[from] ||
            isExcludedFromFees[to];

        if (
            tradingIsEnabled &&
            automatedMarketMakerPairs[from] &&
            !excludedAccount
        ) {
            require(amount <= maxBuyTransactionAmount, "Error amount");

            uint256 contractBalanceRecipient = balanceOf(to);
            require(
                contractBalanceRecipient + amount <= maxWalletToken,
                "Error amount"
            );
        } else if (
            tradingIsEnabled &&
            automatedMarketMakerPairs[to] &&
            !excludedAccount
        ) {
            require(amount <= maxSellTransactionAmount, "Error amount");

            uint256 contractTokenBalance = balanceOf(address(this));

            if (!swapping && contractTokenBalance >= swapTokensAtAmount) {
                swapping = true;

                if (marketingEnabled) {
                    uint256 swapTokens = contractTokenBalance
                        .div(totalFees)
                        .mul(marketingFee);
                    swapTokensForPOM(swapTokens);
                    uint256 marketingPortion = address(this).balance;
                    transferToWallet(
                        payable(marketingWallet),
                        marketingPortion
                    );
                }

                if (buyBackAndLiquifyEnabled) {
                    if (buyBackMode) {
                        swapTokensForPOM(
                            contractTokenBalance.div(totalFees).mul(
                                buyBackAndLiquidityFee
                            )
                        );
                    } else {
                        swapAndLiquify(
                            contractTokenBalance.div(totalFees).mul(
                                buyBackAndLiquidityFee
                            )
                        );
                    }
                }

                if (dividendEnabled) {
                    uint256 sellTokens = contractTokenBalance
                        .div(totalFees)
                        .mul(SpaceDividendRewardsFee);
                    swapAndSendDividends(sellTokens.sub(1300));
                }

                swapping = false;
            }

            if (!swapping && buyBackAndLiquifyEnabled && buyBackMode) {
                uint256 buyBackBalancePom = address(this).balance;
                if (
                    buyBackBalancePom >= minimumBalanceRequired &&
                    amount >= minimumSellOrderAmount
                ) {
                    swapping = true;

                    if (buyBackBalancePom > buyBackUpperLimit) {
                        buyBackBalancePom = buyBackUpperLimit;
                    }

                    buyBackAtom(buyBackBalancePom.div(10 ** 2));

                    swapping = false;
                }
            }
        }

        if (tradingIsEnabled && !swapping && !excludedAccount) {
            uint256 fees = amount.div(100).mul(totalFees);

            // if sell, multiply by sellFeeIncreaseFactor
            if (automatedMarketMakerPairs[to]) {
                fees = fees.div(100).mul(sellFeeIncreaseFactor);
            }

            amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);
        try
            dividendTracker.setBalance(payable(from), balanceOf(from))
        {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}
        if (!swapping) {
            uint256 gas = gasForProcessing;
            if (dividendEnabled && sendInTx) {
                try dividendTracker.process(gas) returns (
                    uint256 iterations,
                    uint256 claims,
                    uint256 lastProcessedIndex
                ) {
                    emit ProcessedDividendTracker(
                        iterations,
                        claims,
                        lastProcessedIndex,
                        true,
                        gas,
                        tx.origin
                    );
                } catch {}
            }
        }
    }

    function swapAndLiquify(uint256 contractTokenBalance) private {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        uint256 initialBalance = address(this).balance;

        swapTokensForPOM(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            marketingWallet,
            block.timestamp
        );
    }

    function buyBackAtom(uint256 amount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        // make the swap
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amount
        }(
            0, // accept any amount of Tokens
            path,
            marketingWallet, // Burn address
            block.timestamp.add(300)
        );
        emit SwapPOMForTokens(amount, path);
    }

    function manualBuyBackAtom(uint256 _amount) public onlyOwner {
        uint256 balance = address(this).balance;
        require(buyBackAndLiquifyEnabled, "not enabled");
        require(
            balance >= minimumBalanceRequired.add(_amount),
            "amount is too big"
        );

        if (!swapping) {
            buyBackAtom(_amount);
        }
    }

    function swapTokensForPOM(uint256 tokenAmount) private {
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

    function swapTokensForDividendToken(
        uint256 _tokenAmount,
        address _recipient,
        address _dividendAddress
    ) private {
        // generate the uniswap pair path of weth -> busd
        // address[] memory path;

        if (_dividendAddress != uniswapV2Router.WETH()) {
            address[] memory path = new address[](3);
            path[0] = address(this);
            path[1] = uniswapV2Router.WETH();
            path[2] = _dividendAddress;
            _approve(address(this), address(uniswapV2Router), _tokenAmount);

            // make the swap

            uniswapV2Router
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _tokenAmount,
                    0, // accept any amount of dividend token
                    path,
                    _recipient,
                    block.timestamp
                );
        } else {
            uint256 initialBalance = address(this).balance;
            swapTokensForPOM(_tokenAmount);
            uint256 amountToDeposit = address(this).balance.sub(initialBalance);
            IWETH(uniswapV2Router.WETH()).deposit{value: amountToDeposit}();
        }
    }

    function withdrawEthBalance() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function swapAndSendDividends(uint256 tokens) private {
        swapTokensForDividendToken(tokens, address(this), rewardToken);
        uint256 dividends = IERC20(rewardToken).balanceOf(address(this));
        transferDividends(
            rewardToken,
            address(dividendTracker),
            dividendTracker,
            dividends
        );
    }

    function transferToWallet(
        address payable recipient,
        uint256 amount
    ) private {
        recipient.transfer(amount);
    }

    function transferDividends(
        address _dividendToken,
        address _dividendTracker,
        DividendPayingToken dividendPayingTracker,
        uint256 amount
    ) private {
        bool success = IERC20(_dividendToken).transfer(
            _dividendTracker,
            amount
        );

        if (success) {
            dividendPayingTracker.distributeDividends(amount);
            emit SendDividends(amount);
        }
    }
}
